-- ============================================================================
-- Aux — Rebuild Phase 3: categories + room instancing + ~20 cap
-- Run AFTER schema.sql + milestone2.sql + milestone3.sql + rebuild.sql.
-- Additive + idempotent.
--
-- Home → categories → rooms. Each genre becomes a CATEGORY holding 1+ room
-- INSTANCES (cap 7 — small + intimate, built for genuine connection). Popularity
-- creates more rooms (Lo-Fi 2), never bigger ones.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Categories (one per genre for now)
-- ----------------------------------------------------------------------------
create table if not exists public.categories (
  id    uuid primary key default gen_random_uuid(),
  name  text not null,
  genre text not null unique,
  sort  int not null default 0
);

insert into public.categories (name, genre, sort) values
  ('2am Lo-Fi',        'lofi',      0),
  ('Hyperpop',         'hyperpop',  1),
  ('2000s Throwbacks', 'throwback', 2),
  ('Bedroom Pop',      'bedroom',   3),
  ('Drum & Bass',      'dnb',       4),
  ('Sad Girl Indie',   'sadindie',  5)
on conflict (genre) do nothing;

alter table public.categories enable row level security;
drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories
  for select to authenticated using (true);

-- ----------------------------------------------------------------------------
-- 2. rooms gain category + instance number; backfill the seeded rooms
-- ----------------------------------------------------------------------------
alter table public.rooms
  add column if not exists category_id uuid references public.categories (id),
  add column if not exists instance_no int not null default 1;

update public.rooms r
   set category_id = c.id
  from public.categories c
 where c.genre = r.genre and r.category_id is null;

-- ----------------------------------------------------------------------------
-- 3. join_category — the cold-start funnel + instancing
-- Returns the room id a newcomer should join.
-- ----------------------------------------------------------------------------
create or replace function public.join_category(p_category_id uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_cap     constant int    := 7;      -- 7 per room: intimate, built for connection
  v_stale   constant bigint := 18000;  -- heartbeat freshness (~lobbyStaleAfter)
  v_now_ms  bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_cat     categories%rowtype;
  v_room_id uuid;
  v_next_no int;
begin
  select * into v_cat from categories where id = p_category_id;
  if v_cat.id is null then raise exception 'category not found'; end if;

  -- 1. fullest ACTIVE instance that still has room (feels alive)
  select id into v_room_id from rooms
   where category_id = p_category_id
     and audience_heartbeat_ms is not null
     and audience_heartbeat_ms > v_now_ms - v_stale
     and coalesce(audience_count, 0) < v_cap
   order by audience_count desc nulls last, instance_no asc
   limit 1;
  if v_room_id is not null then return v_room_id; end if;

  -- 2. an IDLE instance (stale heartbeat ⇒ effectively empty) — reuse before creating
  select id into v_room_id from rooms
   where category_id = p_category_id
     and (audience_heartbeat_ms is null or audience_heartbeat_ms <= v_now_ms - v_stale)
   order by instance_no asc
   limit 1;
  if v_room_id is not null then return v_room_id; end if;

  -- 3. all instances full ⇒ spin up the next one ("<Category> N")
  select coalesce(max(instance_no), 0) + 1 into v_next_no
    from rooms where category_id = p_category_id;
  insert into rooms (name, genre, phase, category_id, instance_no)
  values (v_cat.name || ' ' || v_next_no, v_cat.genre, 'idle', p_category_id, v_next_no)
  returning id into v_room_id;
  return v_room_id;
end;
$$;

grant execute on function public.join_category(uuid) to authenticated;
