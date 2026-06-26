-- ============================================================================
-- Aux — Milestone 1 schema (rotating DJ booth)
-- Run this in the Supabase SQL Editor (one shot). Safe to re-run (idempotent-ish).
--
-- After running:
--   1. Authentication → Providers → enable "Allow anonymous sign-ins".
--   2. Verify Realtime is on for rooms / dj_lineup / votes / messages
--      (the publication block below handles it).
--   3. Paste your Project URL + anon key into Aux/Config/Secrets.swift.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------

-- App-level profile, 1:1 with auth.users (anonymous users included).
create table if not exists public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  handle      text not null,
  avatar      text not null default '🎧',   -- emoji token; no image storage in MVP
  created_at  timestamptz not null default now()
);

-- One row per room. Source of truth for synced playback + rotation phase.
-- Time math on the client uses the *_ms epoch columns (format-agnostic over the
-- wire); the timestamptz columns are kept for readability/debugging.
create table if not exists public.rooms (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null,
  genre                text not null,
  phase                text not null default 'idle'
                         check (phase in ('idle', 'playing', 'picking')),
  current_dj_id        uuid,                       -- null => auto-DJ
  current_track        jsonb,                      -- null during 'picking'
  playback_started_at  timestamptz,
  playback_started_ms  bigint,                     -- epoch ms; client sync basis
  phase_deadline_ms    bigint,                     -- epoch ms; end of 'picking' window
  round_id             uuid                        -- changes every transition (CAS key)
);

-- The DJ rotation. On-deck + all waiting DJs live here, ordered by `position`.
-- Each waiting DJ holds one `cued_track`.
create table if not exists public.dj_lineup (
  room_id     uuid not null references public.rooms (id) on delete cascade,
  user_id     uuid not null references public.users (id) on delete cascade,
  position    bigint not null,
  cued_track  jsonb,
  joined_at   timestamptz not null default now(),
  primary key (room_id, user_id)
);

-- One vote per user per play (round). Powers the reveal + DJ hot-rating.
create table if not exists public.votes (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  round_id    uuid not null,
  track_id    text not null,
  dj_id       uuid,                                -- null when voting on auto-DJ
  voter_id    uuid not null references public.users (id) on delete cascade,
  vote        text not null check (vote in ('hot', 'skip')),
  created_at  timestamptz not null default now(),
  unique (round_id, voter_id)
);

-- Realtime room chat.
create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  user_id     uuid not null references public.users (id) on delete cascade,
  text        text not null,
  created_at  timestamptz not null default now()
);

-- Server-authoritative fallback playlist for the auto-DJ ("never silent").
create table if not exists public.default_tracks (
  id        uuid primary key default gen_random_uuid(),
  genre     text not null,
  position  int not null default 0,
  track     jsonb not null
);

create index if not exists votes_round_idx     on public.votes (round_id);
create index if not exists messages_room_idx   on public.messages (room_id, created_at);
create index if not exists lineup_room_pos_idx on public.dj_lineup (room_id, position);

-- ----------------------------------------------------------------------------
-- RPCs  (all SECURITY DEFINER; they bypass RLS and do their own auth checks)
-- ----------------------------------------------------------------------------

-- Server clock in epoch milliseconds — clients calibrate their offset with this.
create or replace function public.server_now()
returns bigint
language sql stable
as $$
  select (extract(epoch from clock_timestamp()) * 1000)::bigint;
$$;

-- Join the DJ lineup at the back.
create or replace function public.step_up(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_pos bigint;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select coalesce(max(position), 0) + 1 into v_pos
    from dj_lineup where room_id = p_room_id;
  insert into dj_lineup (room_id, user_id, position, cued_track, joined_at)
  values (p_room_id, v_uid, v_pos, null, now())
  on conflict (room_id, user_id) do nothing;
end;
$$;

-- Leave the DJ lineup.
create or replace function public.step_down(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  delete from dj_lineup where room_id = p_room_id and user_id = v_uid;
end;
$$;

-- Cue your next pick. If you're the on-deck DJ in the 'picking' window, your
-- pick starts playing immediately.
create or replace function public.cue_track(p_room_id uuid, p_track jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_room rooms%rowtype;
  v_now  timestamptz := clock_timestamp();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  update dj_lineup set cued_track = p_track
   where room_id = p_room_id and user_id = v_uid;
  if not found then raise exception 'step up to the decks before cueing'; end if;

  select * into v_room from rooms where id = p_room_id for update;
  if v_room.phase = 'picking' and v_room.current_dj_id = v_uid then
    update rooms set
      phase               = 'playing',
      current_track       = p_track,
      playback_started_at = v_now,
      playback_started_ms = (extract(epoch from v_now) * 1000)::bigint,
      phase_deadline_ms   = null,
      round_id            = gen_random_uuid()
    where id = p_room_id;
    update dj_lineup set cued_track = null
     where room_id = p_room_id and user_id = v_uid;
  end if;
end;
$$;

-- The rotation. Idempotent via compare-and-swap on round_id, so every client can
-- safely call it — only the first call that matches the expected round wins.
-- `p_present` is the set of user_ids currently in the room (from Realtime
-- presence); absent DJs are pruned and skipped.
create or replace function public.advance_room(
  p_room_id           uuid,
  p_expected_round_id uuid,
  p_present           uuid[]
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_room           rooms%rowtype;
  v_now            timestamptz := clock_timestamp();
  v_now_ms         bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_next           record;
  v_default        jsonb;
  v_max_pos        bigint;
  v_pick_window_ms constant bigint := 15000;   -- 15s to pick if nothing cued
begin
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then raise exception 'room not found'; end if;

  -- Compare-and-swap guard (null-safe; also matches the null bootstrap round).
  if v_room.round_id is distinct from p_expected_round_id then
    return;
  end if;

  -- Drop DJs who have left the room.
  if p_present is not null then
    delete from dj_lineup
     where room_id = p_room_id and not (user_id = any (p_present));
  end if;

  -- Send the DJ who just played to the back of the line.
  if v_room.current_dj_id is not null then
    select coalesce(max(position), 0) into v_max_pos
      from dj_lineup where room_id = p_room_id;
    update dj_lineup set position = v_max_pos + 1
     where room_id = p_room_id and user_id = v_room.current_dj_id;
  end if;

  -- Next up = lowest-position DJ still present.
  select user_id, cued_track into v_next
    from dj_lineup
   where room_id = p_room_id
   order by position asc
   limit 1;

  if v_next.user_id is not null and v_next.cued_track is not null then
    -- They have a pick cued → play it now.
    update rooms set
      phase               = 'playing',
      current_dj_id       = v_next.user_id,
      current_track       = v_next.cued_track,
      playback_started_at = v_now,
      playback_started_ms = v_now_ms,
      phase_deadline_ms   = null,
      round_id            = gen_random_uuid()
    where id = p_room_id;
    update dj_lineup set cued_track = null
     where room_id = p_room_id and user_id = v_next.user_id;

  elsif v_next.user_id is not null then
    -- On deck but nothing cued → short pick window, then they get skipped.
    update rooms set
      phase               = 'picking',
      current_dj_id       = v_next.user_id,
      current_track       = null,
      playback_started_at = null,
      playback_started_ms = null,
      phase_deadline_ms   = v_now_ms + v_pick_window_ms,
      round_id            = gen_random_uuid()
    where id = p_room_id;

  else
    -- Empty lineup → auto-DJ from the default playlist (never silent).
    select track into v_default
      from default_tracks
     where genre = v_room.genre
       and (v_room.current_track is null
            or track ->> 'trackId' is distinct from v_room.current_track ->> 'trackId')
     order by random()
     limit 1;
    if v_default is null then
      select track into v_default from default_tracks
       where genre = v_room.genre order by random() limit 1;
    end if;

    update rooms set
      phase               = 'playing',
      current_dj_id       = null,
      current_track       = v_default,
      playback_started_at = v_now,
      playback_started_ms = v_now_ms,
      phase_deadline_ms   = null,
      round_id            = gen_random_uuid()
    where id = p_room_id;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------

alter table public.users          enable row level security;
alter table public.rooms          enable row level security;
alter table public.dj_lineup      enable row level security;
alter table public.votes          enable row level security;
alter table public.messages       enable row level security;
alter table public.default_tracks enable row level security;

-- Room data is readable by any signed-in user (anonymous included).
drop policy if exists users_select on public.users;
create policy users_select on public.users
  for select to authenticated using (true);

drop policy if exists users_upsert on public.users;
create policy users_upsert on public.users
  for insert to authenticated with check (id = auth.uid());

drop policy if exists users_update on public.users;
create policy users_update on public.users
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms
  for select to authenticated using (true);

drop policy if exists lineup_select on public.dj_lineup;
create policy lineup_select on public.dj_lineup
  for select to authenticated using (true);

drop policy if exists votes_select on public.votes;
create policy votes_select on public.votes
  for select to authenticated using (true);

drop policy if exists votes_insert on public.votes;
create policy votes_insert on public.votes
  for insert to authenticated with check (voter_id = auth.uid());

drop policy if exists votes_update on public.votes;
create policy votes_update on public.votes
  for update to authenticated using (voter_id = auth.uid()) with check (voter_id = auth.uid());

drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select to authenticated using (true);

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists default_tracks_select on public.default_tracks;
create policy default_tracks_select on public.default_tracks
  for select to authenticated using (true);

-- rooms / dj_lineup have NO direct client write policies on purpose — every
-- mutation goes through the SECURITY DEFINER RPCs above.

grant execute on function public.server_now()                     to authenticated;
grant execute on function public.step_up(uuid)                    to authenticated;
grant execute on function public.step_down(uuid)                  to authenticated;
grant execute on function public.cue_track(uuid, jsonb)           to authenticated;
grant execute on function public.advance_room(uuid, uuid, uuid[]) to authenticated;

-- ----------------------------------------------------------------------------
-- Realtime (postgres_changes) — add tables to the publication + full row images
-- ----------------------------------------------------------------------------

alter table public.rooms     replica identity full;
alter table public.dj_lineup replica identity full;
alter table public.votes     replica identity full;
alter table public.messages  replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rooms') then
    alter publication supabase_realtime add table public.rooms;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dj_lineup') then
    alter publication supabase_realtime add table public.dj_lineup;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'votes') then
    alter publication supabase_realtime add table public.votes;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- Seed: the single Milestone-1 room + the auto-DJ fallback playlist
-- The room id is hardcoded so the client can target it (RoomConfig.roomID).
-- ----------------------------------------------------------------------------

insert into public.rooms (id, name, genre, phase)
values ('11111111-1111-1111-1111-111111111111', '2am Lo-Fi', 'lofi', 'idle')
on conflict (id) do nothing;

-- Wipe + reseed the lofi fallback (real iTunes 30s previews).
delete from public.default_tracks where genre = 'lofi';
insert into public.default_tracks (genre, position, track) values
('lofi', 0, '{"trackId":"1541926438","trackName":"Lofi Chill","artistName":"Lofi Sleep Chill & Study","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/71/15/c5/7115c542-cf70-35f6-e2e9-d2131ff538a2/5055803554880.png/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/10/0f/e6/100fe64f-0815-a9d5-9bec-e375ddd5a733/mzaf_8225005754342783380.plus.aac.p.m4a"}'),
('lofi', 1, '{"trackId":"1448744408","trackName":"Lofi Chill (Instrumental)","artistName":"LoFi Hip Hop","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/d3/eb/fc/d3ebfcab-4693-06fa-d3a2-4cd82d7cd787/1979.jpg/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/b0/9d/9d/b09d9dcb-f766-3822-5eab-912d99fbd061/mzaf_11357376625040044236.plus.aac.p.m4a"}'),
('lofi', 2, '{"trackId":"6778332040","trackName":"Coffee Break - Lo-Fi Chill Cafe","artistName":"FM STAR","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/46/a7/02/46a702e8-32f6-af5a-2370-41aaa6e94c06/4550757510148_cover.png/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/b7/8a/24/b78a2444-175f-c72d-8209-ef78a56eb94e/mzaf_3361843330503354025.plus.aac.p.m4a"}'),
('lofi', 3, '{"trackId":"1559528072","trackName":"Lofi Chill","artistName":"Lofi Sleep Chill & Study","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/4e/69/8b/4e698ba6-a4b4-7683-b85e-faf04b317c72/5055803577049.png/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview124/v4/13/83/97/138397ab-3e9f-d1d6-9156-58423faa06d8/mzaf_7838088630732759371.plus.aac.p.m4a"}'),
('lofi', 4, '{"trackId":"1537465145","trackName":"Lofi Chill","artistName":"ChillHop","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/41/05/85/410585d7-06bb-b6a2-1a6b-fb9c28317c64/13924.jpg/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/c1/f1/97/c1f197ff-c31b-1440-b6b5-e5402e17c6a9/mzaf_3867569384683790362.plus.aac.p.m4a"}'),
('lofi', 5, '{"trackId":"6778331716","trackName":"Weekend Vibes - Chill Holiday Lo-Fi","artistName":"FM STAR","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/46/a7/02/46a702e8-32f6-af5a-2370-41aaa6e94c06/4550757510148_cover.png/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/d9/91/bd/d991bdb8-d9c3-d0a0-4fb5-17aa0895fb4c/mzaf_960030085854036949.plus.aac.p.m4a"}'),
('lofi', 6, '{"trackId":"6778331711","trackName":"Midnight Reading - Relaxing Lo-Fi Jazz","artistName":"FM STAR","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/46/a7/02/46a702e8-32f6-af5a-2370-41aaa6e94c06/4550757510148_cover.png/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/59/6d/28/596d2870-654a-c5ba-9625-d91bd182ea15/mzaf_4294964548766225350.plus.aac.p.m4a"}'),
('lofi', 7, '{"trackId":"6778331717","trackName":"Lo-Fi Morning Coffee - Relaxing Cafe Sounds","artistName":"FM STAR","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/46/a7/02/46a702e8-32f6-af5a-2370-41aaa6e94c06/4550757510148_cover.png/100x100bb.jpg","previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/2c/b8/15/2cb81557-8883-1c9f-2dc4-922ec48e95ee/mzaf_17514383532747024121.plus.aac.p.m4a"}');
