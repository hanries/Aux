-- ============================================================================
-- Aux — Rebuild Phase 1: the people-first room engine
-- Run AFTER schema.sql + milestone2.sql + milestone3.sql, in the SQL Editor.
-- Additive + idempotent.
--
-- Pivots the room from hot/skip voting + per-track DJ rotation to:
--   • reactions (fire/hands/laugh/wave/love) — live + attributed; no vote/reveal
--   • a single DJ holding the decks for a SET of clips by POSSESSION
--     (keeps by default; passes only on leave / idle-grace / sustained-cold)
--   • taste twins computed from love-reaction overlap
-- `votes` + `advance_room` are left dormant (not dropped).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Columns
-- ----------------------------------------------------------------------------
alter table public.rooms
  add column if not exists cold_streak int not null default 0;

-- The on-deck DJ's upcoming clips (their "set"); cued_track left dormant.
alter table public.dj_lineup
  add column if not exists cued_set jsonb not null default '[]'::jsonb;

-- ----------------------------------------------------------------------------
-- 2. Reactions — the primary action (replaces votes)
-- ----------------------------------------------------------------------------
create table if not exists public.reactions (
  id             uuid primary key default gen_random_uuid(),
  room_id        uuid not null references public.rooms (id) on delete cascade,
  round_id       uuid,
  track_id       text,
  dj_id          uuid,
  user_id        uuid not null references public.users (id) on delete cascade,
  type           text not null check (type in ('fire','hands','laugh','wave','love')),
  target_user_id uuid,
  track          jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists reactions_round_idx on public.reactions (round_id);
create index if not exists reactions_room_time_idx on public.reactions (room_id, created_at);
create index if not exists reactions_love_idx on public.reactions (room_id, user_id) where type = 'love';

alter table public.reactions enable row level security;

drop policy if exists reactions_select on public.reactions;
create policy reactions_select on public.reactions
  for select to authenticated using (true);

drop policy if exists reactions_insert on public.reactions;
create policy reactions_insert on public.reactions
  for insert to authenticated with check (user_id = auth.uid());

alter table public.reactions replica identity full;
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reactions') then
    alter publication supabase_realtime add table public.reactions;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 3. Cue a clip into my set (and start immediately if I'm on deck mid-grace)
-- ----------------------------------------------------------------------------
create or replace function public.cue_set(p_room_id uuid, p_track jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room rooms%rowtype;
  v_now  timestamptz := clock_timestamp();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  update dj_lineup set cued_set = cued_set || jsonb_build_array(p_track)
   where room_id = p_room_id and user_id = v_uid;
  if not found then raise exception 'step up to the decks before cueing'; end if;

  -- If I'm on deck in the cue-grace window, kick off my set right now.
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.phase = 'picking' and v_room.current_dj_id = v_uid then
    update rooms set
      phase = 'playing', current_track = p_track,
      playback_started_at = v_now,
      playback_started_ms = (extract(epoch from v_now) * 1000)::bigint,
      phase_deadline_ms = null, round_id = gen_random_uuid()
    where id = p_room_id;
    update dj_lineup set cued_set = cued_set - 0
     where room_id = p_room_id and user_id = v_uid;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. advance_set — set advance + possession + cold (replaces advance_room)
-- ----------------------------------------------------------------------------
create or replace function public.advance_set(
  p_room_id           uuid,
  p_expected_round_id uuid,
  p_present           uuid[]
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_room        rooms%rowtype;
  v_now         timestamptz := clock_timestamp();
  v_now_ms      bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_reactions   int := 0;
  v_cold        int := 0;
  v_head        jsonb;
  v_next        record;
  v_default     jsonb;
  v_keep        boolean;
  v_cold_floor  constant int := 2;       -- < this many reactions/clip = cold
  v_cold_limit  constant int := 3;       -- cold this many clips in a row = pass
  v_grace_ms    constant bigint := 20000;-- cue-grace before an idle DJ forfeits
begin
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then raise exception 'room not found'; end if;
  if v_room.round_id is distinct from p_expected_round_id then return; end if;

  if p_present is not null then
    delete from dj_lineup where room_id = p_room_id and not (user_id = any (p_present));
  end if;

  -- Warmth of the clip that just finished → cold streak.
  if v_room.round_id is not null then
    select count(*) into v_reactions from reactions where round_id = v_room.round_id;
  end if;
  v_cold := case when v_reactions < v_cold_floor then v_room.cold_streak + 1 else 0 end;

  -- Does the current DJ keep the decks?
  v_keep := v_room.current_dj_id is not null
        and (p_present is null or v_room.current_dj_id = any (p_present))
        and v_cold < v_cold_limit;

  if v_keep then
    select cued_set -> 0 into v_head
      from dj_lineup where room_id = p_room_id and user_id = v_room.current_dj_id;
    if v_head is not null then
      -- play their next set clip
      update dj_lineup set cued_set = cued_set - 0
        where room_id = p_room_id and user_id = v_room.current_dj_id;
      update rooms set
        phase = 'playing', current_track = v_head,
        playback_started_at = v_now, playback_started_ms = v_now_ms,
        phase_deadline_ms = null, round_id = gen_random_uuid(), cold_streak = v_cold
      where id = p_room_id;
      perform public.refresh_lineup_count(p_room_id);
      return;
    elsif v_room.phase <> 'picking' then
      -- first time their set ran dry → give a cue-grace, keep them on deck
      update rooms set
        phase = 'picking', current_track = null,
        playback_started_at = null, playback_started_ms = null,
        phase_deadline_ms = v_now_ms + v_grace_ms,
        round_id = gen_random_uuid(), cold_streak = v_cold
      where id = p_room_id;
      perform public.refresh_lineup_count(p_room_id);
      return;
    end if;
    -- else: grace already given and still empty → fall through (forfeit)
  end if;

  -- The current DJ loses the decks → send them to the back of the line.
  if v_room.current_dj_id is not null then
    update dj_lineup
      set position = (select coalesce(max(position), 0) + 1 from dj_lineup where room_id = p_room_id)
      where room_id = p_room_id and user_id = v_room.current_dj_id;
  end if;

  -- Next: lowest-position present DJ who has a cued clip.
  select user_id, cued_set -> 0 as head into v_next
    from dj_lineup
   where room_id = p_room_id and jsonb_array_length(cued_set) > 0
   order by position asc limit 1;

  if v_next.user_id is not null then
    update dj_lineup set cued_set = cued_set - 0
      where room_id = p_room_id and user_id = v_next.user_id;
    update rooms set
      phase = 'playing', current_dj_id = v_next.user_id, current_track = v_next.head,
      playback_started_at = v_now, playback_started_ms = v_now_ms,
      phase_deadline_ms = null, round_id = gen_random_uuid(), cold_streak = 0
    where id = p_room_id;
  else
    -- someone in line but nothing cued → cue-grace for the front DJ
    select user_id into v_next from dj_lineup
     where room_id = p_room_id order by position asc limit 1;
    if v_next.user_id is not null then
      update rooms set
        phase = 'picking', current_dj_id = v_next.user_id, current_track = null,
        playback_started_at = null, playback_started_ms = null,
        phase_deadline_ms = v_now_ms + v_grace_ms,
        round_id = gen_random_uuid(), cold_streak = 0
      where id = p_room_id;
    else
      -- empty booth → auto-DJ (never silent)
      select track into v_default from default_tracks
       where genre = v_room.genre
         and (v_room.current_track is null
              or track ->> 'trackId' is distinct from v_room.current_track ->> 'trackId')
       order by random() limit 1;
      if v_default is null then
        select track into v_default from default_tracks
         where genre = v_room.genre order by random() limit 1;
      end if;
      update rooms set
        phase = 'playing', current_dj_id = null, current_track = v_default,
        playback_started_at = v_now, playback_started_ms = v_now_ms,
        phase_deadline_ms = null, round_id = gen_random_uuid(), cold_streak = 0
      where id = p_room_id;
    end if;
  end if;

  perform public.refresh_lineup_count(p_room_id);
end;
$$;

-- small helper so the lobby's lineup_count stays fresh
create or replace function public.refresh_lineup_count(p_room_id uuid)
returns void language sql security definer set search_path = public as $$
  update rooms set lineup_count = (select count(*) from dj_lineup where room_id = p_room_id)
   where id = p_room_id;
$$;

-- ----------------------------------------------------------------------------
-- 5. Taste twins from love-reaction overlap (replaces the vote-overlap version)
-- ----------------------------------------------------------------------------
create or replace function public.taste_twins(
  p_room_id         uuid,
  p_min_shared      int default 3,
  p_recency_minutes int default 240
) returns table (
  other_id          uuid,
  handle            text,
  avatar            text,
  shared            int,
  agree             int,
  agreement         double precision,
  shared_hot        int,
  shared_hot_tracks jsonb
)
language sql security definer set search_path = public
as $$
  with me as (
    select distinct track_id, track from reactions
     where user_id = auth.uid() and room_id = p_room_id and type = 'love'
       and created_at > now() - make_interval(mins => p_recency_minutes)
  ),
  others as (
    select distinct user_id, track_id, track from reactions
     where room_id = p_room_id and user_id <> auth.uid() and type = 'love'
       and created_at > now() - make_interval(mins => p_recency_minutes)
  )
  select
    o.user_id, u.handle, u.avatar,
    count(*)::int            as shared,        -- tracks you both loved
    count(*)::int            as agree,
    1.0::double precision    as agreement,     -- both loved ⇒ full agreement
    count(*)::int            as shared_hot,
    coalesce(
      jsonb_agg(distinct coalesce(o.track, m.track))
        filter (where coalesce(o.track, m.track) is not null),
      '[]'::jsonb)           as shared_hot_tracks
  from others o
  join me    m on m.track_id = o.track_id
  join users u on u.id = o.user_id
  where not public.is_blocked(auth.uid(), o.user_id)
  group by o.user_id, u.handle, u.avatar
  having count(*) >= p_min_shared
  order by shared desc
  limit 20;
$$;

-- ----------------------------------------------------------------------------
-- 6. Grants
-- ----------------------------------------------------------------------------
grant execute on function public.cue_set(uuid, jsonb)             to authenticated;
grant execute on function public.advance_set(uuid, uuid, uuid[])  to authenticated;
grant execute on function public.refresh_lineup_count(uuid)       to authenticated;
