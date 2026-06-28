-- ============================================================================
-- Aux — Milestone 3 migration (the connection layer)
-- Run AFTER schema.sql + milestone2.sql, in the Supabase SQL Editor.
-- Additive + idempotent. Adds taste twins, follow, 1:1 DM, and block — with
-- Row-Level Security so users only read their own relationships/threads.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Columns: per-user "where am I now" + per-vote track metadata
-- ----------------------------------------------------------------------------
alter table public.users
  add column if not exists current_room_id       uuid,
  add column if not exists presence_heartbeat_ms  bigint;

-- The played Track is denormalized onto each vote so taste_twins can show the
-- "you both loved these" tracks by name.
alter table public.votes
  add column if not exists track jsonb;

-- ----------------------------------------------------------------------------
-- 2. Tables (writes go through SECURITY DEFINER RPCs; selects via RLS)
-- ----------------------------------------------------------------------------
create table if not exists public.follows (
  follower_id uuid not null references public.users (id) on delete cascade,
  followee_id uuid not null references public.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists follows_followee_idx on public.follows (followee_id);

create table if not exists public.blocks (
  blocker_id uuid not null references public.users (id) on delete cascade,
  blocked_id uuid not null references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- One row per 1:1 thread. user_lo < user_hi (sorted) makes find-or-create unique.
create table if not exists public.dms (
  id             uuid primary key default gen_random_uuid(),
  user_lo        uuid not null references public.users (id) on delete cascade,
  user_hi        uuid not null references public.users (id) on delete cascade,
  created_at     timestamptz not null default now(),
  last_text      text,
  last_ms        bigint,
  last_sender_id uuid,
  read_lo_ms     bigint not null default 0,
  read_hi_ms     bigint not null default 0,
  unique (user_lo, user_hi),
  check (user_lo < user_hi)
);

create table if not exists public.dm_messages (
  id         uuid primary key default gen_random_uuid(),
  dm_id      uuid not null references public.dms (id) on delete cascade,
  sender_id  uuid not null references public.users (id) on delete cascade,
  text       text not null,
  created_at timestamptz not null default now(),
  created_ms bigint not null default (extract(epoch from clock_timestamp()) * 1000)::bigint
);
create index if not exists dm_messages_thread_idx on public.dm_messages (dm_id, created_ms);

-- ----------------------------------------------------------------------------
-- 3. RLS — read your own relationships/threads only
-- ----------------------------------------------------------------------------
alter table public.follows     enable row level security;
alter table public.blocks      enable row level security;
alter table public.dms         enable row level security;
alter table public.dm_messages enable row level security;

drop policy if exists follows_select on public.follows;
create policy follows_select on public.follows for select to authenticated
  using (follower_id = auth.uid() or followee_id = auth.uid());

drop policy if exists blocks_select on public.blocks;
create policy blocks_select on public.blocks for select to authenticated
  using (blocker_id = auth.uid());

drop policy if exists dms_select on public.dms;
create policy dms_select on public.dms for select to authenticated
  using (auth.uid() in (user_lo, user_hi));

drop policy if exists dm_messages_select on public.dm_messages;
create policy dm_messages_select on public.dm_messages for select to authenticated
  using (exists (
    select 1 from public.dms d
    where d.id = dm_id and auth.uid() in (d.user_lo, d.user_hi)
  ));

-- follows / blocks / dms / dm_messages have NO write policies — all mutations go
-- through the SECURITY DEFINER RPCs below.

-- ----------------------------------------------------------------------------
-- 4. Helpers + RPCs
-- ----------------------------------------------------------------------------

create or replace function public.is_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

-- Taste twins: vote agreement with everyone you share votes with this session.
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
    select track_id, vote, track from votes
     where voter_id = auth.uid() and room_id = p_room_id
       and created_at > now() - make_interval(mins => p_recency_minutes)
  ),
  others as (
    select voter_id, track_id, vote, track from votes
     where room_id = p_room_id and voter_id <> auth.uid()
       and created_at > now() - make_interval(mins => p_recency_minutes)
  )
  select
    o.voter_id,
    u.handle,
    u.avatar,
    count(*)::int                                            as shared,
    count(*) filter (where o.vote = m.vote)::int             as agree,
    (count(*) filter (where o.vote = m.vote))::double precision / count(*) as agreement,
    count(*) filter (where o.vote = 'hot' and m.vote = 'hot')::int as shared_hot,
    coalesce(
      jsonb_agg(distinct coalesce(o.track, m.track))
        filter (where o.vote = 'hot' and m.vote = 'hot'
                 and coalesce(o.track, m.track) is not null),
      '[]'::jsonb)                                           as shared_hot_tracks
  from others o
  join me     m on m.track_id = o.track_id
  join users  u on u.id = o.voter_id
  where not public.is_blocked(auth.uid(), o.voter_id)
  group by o.voter_id, u.handle, u.avatar
  having count(*) >= p_min_shared
  order by agreement desc, shared desc
  limit 20;
$$;

-- Per-user presence: which room am I in right now (drives "your people are live").
create or replace function public.set_presence(p_room_id uuid)
returns void language sql security definer set search_path = public
as $$
  update public.users
     set current_room_id       = p_room_id,
         presence_heartbeat_ms  = (extract(epoch from clock_timestamp()) * 1000)::bigint
   where id = auth.uid();
$$;

create or replace function public.follow_user(p_other uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v uuid := auth.uid();
begin
  if v is null or v = p_other then raise exception 'bad follow'; end if;
  if public.is_blocked(v, p_other) then raise exception 'blocked'; end if;
  insert into follows (follower_id, followee_id) values (v, p_other)
    on conflict do nothing;
end;
$$;

create or replace function public.unfollow_user(p_other uuid)
returns void language sql security definer set search_path = public
as $$
  delete from follows where follower_id = auth.uid() and followee_id = p_other;
$$;

create or replace function public.find_or_create_dm(p_other uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v uuid := auth.uid(); v_lo uuid; v_hi uuid; v_id uuid;
begin
  if v is null or v = p_other then raise exception 'bad dm'; end if;
  if public.is_blocked(v, p_other) then raise exception 'blocked'; end if;
  v_lo := least(v, p_other); v_hi := greatest(v, p_other);
  insert into dms (user_lo, user_hi) values (v_lo, v_hi)
    on conflict (user_lo, user_hi) do nothing;
  select id into v_id from dms where user_lo = v_lo and user_hi = v_hi;
  return v_id;
end;
$$;

create or replace function public.send_dm(p_dm_id uuid, p_text text)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v       uuid := auth.uid();
  d       dms%rowtype;
  v_other uuid;
  v_ms    bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  select * into d from dms where id = p_dm_id for update;
  if d.id is null then raise exception 'no thread'; end if;
  if v not in (d.user_lo, d.user_hi) then raise exception 'not a member'; end if;
  v_other := case when v = d.user_lo then d.user_hi else d.user_lo end;
  if public.is_blocked(v, v_other) then raise exception 'blocked'; end if;
  if length(coalesce(p_text, '')) = 0 then return; end if;

  insert into dm_messages (dm_id, sender_id, text, created_ms)
  values (p_dm_id, v, p_text, v_ms);

  update dms set
    last_text      = p_text,
    last_ms        = v_ms,
    last_sender_id = v,
    read_lo_ms     = case when v = user_lo then v_ms else read_lo_ms end,
    read_hi_ms     = case when v = user_hi then v_ms else read_hi_ms end
  where id = p_dm_id;
end;
$$;

create or replace function public.mark_dm_read(p_dm_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v uuid := auth.uid(); v_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  update dms set
    read_lo_ms = case when v = user_lo then v_ms else read_lo_ms end,
    read_hi_ms = case when v = user_hi then v_ms else read_hi_ms end
  where id = p_dm_id and v in (user_lo, user_hi);
end;
$$;

create or replace function public.block_user(p_other uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare v uuid := auth.uid();
begin
  if v is null or v = p_other then raise exception 'bad block'; end if;
  insert into blocks (blocker_id, blocked_id) values (v, p_other) on conflict do nothing;
  delete from follows
   where (follower_id = v and followee_id = p_other)
      or (follower_id = p_other and followee_id = v);
end;
$$;

create or replace function public.unblock_user(p_other uuid)
returns void language sql security definer set search_path = public
as $$
  delete from blocks where blocker_id = auth.uid() and blocked_id = p_other;
$$;

-- People I follow + whether they're live right now (and where).
create or replace function public.my_following(p_stale_ms bigint default 30000)
returns table (
  user_id uuid, handle text, avatar text,
  room_id uuid, room_name text, is_live boolean
)
language sql security definer set search_path = public
as $$
  select
    u.id, u.handle, u.avatar, u.current_room_id, r.name,
    (u.current_room_id is not null
       and u.presence_heartbeat_ms is not null
       and u.presence_heartbeat_ms >
           (extract(epoch from clock_timestamp()) * 1000)::bigint - p_stale_ms) as is_live
  from follows f
  join users u on u.id = f.followee_id
  left join rooms r on r.id = u.current_room_id
  where f.follower_id = auth.uid()
  order by is_live desc, u.handle;
$$;

-- People who follow me (+ do I follow back) — powers the followers list/badge.
create or replace function public.my_followers()
returns table (user_id uuid, handle text, avatar text, i_follow_back boolean)
language sql security definer set search_path = public
as $$
  select u.id, u.handle, u.avatar,
    exists (select 1 from follows f2
             where f2.follower_id = auth.uid() and f2.followee_id = u.id)
  from follows f
  join users u on u.id = f.follower_id
  where f.followee_id = auth.uid()
  order by u.handle;
$$;

-- My DM threads with the other party + last message + unread flag.
create or replace function public.my_dms()
returns table (
  dm_id uuid, other_id uuid, other_handle text, other_avatar text,
  last_text text, last_ms bigint, last_sender_id uuid, unread boolean
)
language sql security definer set search_path = public
as $$
  select
    d.id,
    case when auth.uid() = d.user_lo then d.user_hi else d.user_lo end,
    u.handle, u.avatar, d.last_text, d.last_ms, d.last_sender_id,
    (d.last_ms is not null
      and d.last_sender_id <> auth.uid()
      and d.last_ms > case when auth.uid() = d.user_lo then d.read_lo_ms else d.read_hi_ms end) as unread
  from dms d
  join users u on u.id = case when auth.uid() = d.user_lo then d.user_hi else d.user_lo end
  where auth.uid() in (d.user_lo, d.user_hi) and d.last_ms is not null
  order by d.last_ms desc;
$$;

-- ----------------------------------------------------------------------------
-- 5. Grants + realtime
-- ----------------------------------------------------------------------------
grant execute on function public.taste_twins(uuid, int, int)   to authenticated;
grant execute on function public.set_presence(uuid)            to authenticated;
grant execute on function public.follow_user(uuid)             to authenticated;
grant execute on function public.unfollow_user(uuid)           to authenticated;
grant execute on function public.find_or_create_dm(uuid)       to authenticated;
grant execute on function public.send_dm(uuid, text)           to authenticated;
grant execute on function public.mark_dm_read(uuid)            to authenticated;
grant execute on function public.block_user(uuid)              to authenticated;
grant execute on function public.unblock_user(uuid)            to authenticated;
grant execute on function public.my_following(bigint)          to authenticated;
grant execute on function public.my_followers()                to authenticated;
grant execute on function public.my_dms()                      to authenticated;

alter table public.dms         replica identity full;
alter table public.dm_messages replica identity full;
alter table public.follows     replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dms') then
    alter publication supabase_realtime add table public.dms;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dm_messages') then
    alter publication supabase_realtime add table public.dm_messages;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'follows') then
    alter publication supabase_realtime add table public.follows;
  end if;
end $$;
