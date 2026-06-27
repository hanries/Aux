-- ============================================================================
-- Aux — Milestone 2 migration (breadth + live lobby)
-- Run AFTER schema.sql, in the Supabase SQL Editor. Additive + idempotent.
--
-- Adds: live lobby metadata columns on rooms, a room_heartbeat RPC, lineup_count
-- upkeep in the lineup RPCs, and 5 more seeded rooms + their auto-DJ playlists.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Live lobby metadata, denormalized onto rooms (one realtime subscription)
-- ----------------------------------------------------------------------------
alter table public.rooms
  add column if not exists audience_count        int    not null default 0,
  add column if not exists audience_heartbeat_ms bigint,
  add column if not exists lineup_count          int    not null default 0;

-- The room leader writes this on presence change + every ~8s. The lobby treats a
-- stale heartbeat as an idle room (count 0), so empty rooms self-heal.
create or replace function public.room_heartbeat(p_room_id uuid, p_count int)
returns void
language sql security definer set search_path = public
as $$
  update public.rooms
     set audience_count        = greatest(p_count, 0),
         audience_heartbeat_ms = (extract(epoch from clock_timestamp()) * 1000)::bigint
   where id = p_room_id;
$$;

grant execute on function public.room_heartbeat(uuid, int) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Keep rooms.lineup_count in sync (recreate the lineup-mutating RPCs)
-- ----------------------------------------------------------------------------

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
  update rooms set lineup_count =
    (select count(*) from dj_lineup where room_id = p_room_id) where id = p_room_id;
end;
$$;

create or replace function public.step_down(p_room_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  delete from dj_lineup where room_id = p_room_id and user_id = v_uid;
  update rooms set lineup_count =
    (select count(*) from dj_lineup where room_id = p_room_id) where id = p_room_id;
end;
$$;

-- advance_room: same rotation as schema.sql, plus a lineup_count refresh at the end.
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
  v_pick_window_ms constant bigint := 15000;
begin
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then raise exception 'room not found'; end if;

  if v_room.round_id is distinct from p_expected_round_id then
    return;
  end if;

  if p_present is not null then
    delete from dj_lineup
     where room_id = p_room_id and not (user_id = any (p_present));
  end if;

  if v_room.current_dj_id is not null then
    select coalesce(max(position), 0) into v_max_pos
      from dj_lineup where room_id = p_room_id;
    update dj_lineup set position = v_max_pos + 1
     where room_id = p_room_id and user_id = v_room.current_dj_id;
  end if;

  select user_id, cued_track into v_next
    from dj_lineup
   where room_id = p_room_id
   order by position asc
   limit 1;

  if v_next.user_id is not null and v_next.cued_track is not null then
    update rooms set
      phase = 'playing', current_dj_id = v_next.user_id, current_track = v_next.cued_track,
      playback_started_at = v_now, playback_started_ms = v_now_ms,
      phase_deadline_ms = null, round_id = gen_random_uuid()
    where id = p_room_id;
    update dj_lineup set cued_track = null
     where room_id = p_room_id and user_id = v_next.user_id;

  elsif v_next.user_id is not null then
    update rooms set
      phase = 'picking', current_dj_id = v_next.user_id, current_track = null,
      playback_started_at = null, playback_started_ms = null,
      phase_deadline_ms = v_now_ms + v_pick_window_ms, round_id = gen_random_uuid()
    where id = p_room_id;

  else
    select track into v_default
      from default_tracks
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
      phase_deadline_ms = null, round_id = gen_random_uuid()
    where id = p_room_id;
  end if;

  update rooms set lineup_count =
    (select count(*) from dj_lineup where room_id = p_room_id) where id = p_room_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. Seed 5 more rooms (fixed ids so the client/debugging can target them)
-- ----------------------------------------------------------------------------
insert into public.rooms (id, name, genre, phase) values
  ('22222222-2222-2222-2222-222222222222', 'Hyperpop',         'hyperpop',  'idle'),
  ('33333333-3333-3333-3333-333333333333', '2000s Throwbacks', 'throwback', 'idle'),
  ('44444444-4444-4444-4444-444444444444', 'Bedroom Pop',      'bedroom',   'idle'),
  ('55555555-5555-5555-5555-555555555555', 'Drum & Bass',      'dnb',       'idle'),
  ('66666666-6666-6666-6666-666666666666', 'Sad Girl Indie',   'sadindie',  'idle')
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 4. Auto-DJ fallback playlists per genre (real iTunes 30s previews)
-- ----------------------------------------------------------------------------
delete from public.default_tracks where genre in ('hyperpop','throwback','bedroom','dnb','sadindie');
insert into public.default_tracks (genre, position, track) values
('hyperpop', 0, '{"trackId": "1617839611", "trackName": "Summertime Blood (feat. Bladee & Ecco2k)", "artistName": "Yung Lean & Skrillex", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/bb/15/e5/bb15e511-aee8-5836-69aa-5a9f53922513/8720766194363.png/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/20/77/4a/20774ae3-fa54-bdb8-d56a-e2b3c3524d48/mzaf_632853702023818820.plus.aac.p.m4a"}'),
('hyperpop', 1, '{"trackId": "1528286969", "trackName": "Vyzee", "artistName": "SOPHIE", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/64/e4/49/64e44935-1bb0-2fb5-baab-ca8a41e8ffb9/cover.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/31/08/4c/31084ccc-d263-5e54-6ea6-5bc3cb95604a/mzaf_12216851547407094053.plus.aac.p.m4a"}'),
('hyperpop', 2, '{"trackId": "1145026107", "trackName": "Trampoline", "artistName": "Kero Kero Bonito", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/54/b8/bd/54b8bdc4-e4dd-465b-dda4-6224d6f14e68/5054526648548_1.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/2b/43/b4/2b43b485-e1fd-0fe5-b0b5-a2912144b01b/mzaf_4113324158825552961.plus.aac.p.m4a"}'),
('hyperpop', 3, '{"trackId": "1651350060", "trackName": "Hyperpop", "artistName": "Oliver Price & Thomas Greenwood", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/80/2e/ed/802eed14-c0d2-5daf-e566-c4628dca74b0/cover.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/24/8e/fb/248efb84-2bed-3a7c-ad68-c0eee159cce5/mzaf_1245382769174661058.plus.aac.p.m4a"}'),
('hyperpop', 4, '{"trackId": "1534065841", "trackName": "Hyperpop", "artistName": "Platinum Beats", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/55/cd/73/55cd737a-5701-11f7-c8f7-2322f377fe91/artwork.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview114/v4/80/eb/d5/80ebd552-7117-e5d8-e2e5-76c132c739ba/mzaf_17065937681642095994.plus.aac.p.m4a"}'),
('hyperpop', 5, '{"trackId": "1655225324", "trackName": "757", "artistName": "100 gecs", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/7b/16/c9/7b16c9c2-a738-66c6-0476-65f020d5dc24/075679708069.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/9f/6a/b1/9f6ab19d-5b37-3167-f1a0-496e64a69eb3/mzaf_2788763006700994351.plus.aac.p.m4a"}'),
('throwback', 0, '{"trackId": "1365412152", "trackName": "Me & U", "artistName": "Cassie", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/e4/8c/22/e48c222a-9a4c-d57d-10d2-1f80b85fb557/842474155462.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/32/bf/4f/32bf4f39-9098-3a2b-3157-cc34cf400d53/mzaf_16561101904926117244.plus.aac.p.m4a"}'),
('throwback', 1, '{"trackId": "1365408228", "trackName": "Cant Get You Out of My Head", "artistName": "Kylie Minogue", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/e4/8c/22/e48c222a-9a4c-d57d-10d2-1f80b85fb557/842474155462.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/5d/8e/b1/5d8eb1a3-9a39-38f6-98f4-1b1d5ad5f33d/mzaf_375613879429937192.plus.aac.p.m4a"}'),
('throwback', 2, '{"trackId": "1365409756", "trackName": "Your Woman", "artistName": "Sunshine Anderson", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/e4/8c/22/e48c222a-9a4c-d57d-10d2-1f80b85fb557/842474155462.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/8b/74/44/8b7444f6-1a0c-fbd6-bb65-4fdaf1f27c66/mzaf_2939619976260315771.plus.aac.p.m4a"}'),
('throwback', 3, '{"trackId": "1365420466", "trackName": "Day Dreamin", "artistName": "Anthony Hamilton", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/e4/8c/22/e48c222a-9a4c-d57d-10d2-1f80b85fb557/842474155462.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/d8/3e/ef/d83eefac-03db-92d5-3fd7-3d60a1a05197/mzaf_2766648386532563598.plus.aac.p.m4a"}'),
('bedroom', 0, '{"trackId": "1512318907", "trackName": "I Know You", "artistName": "Faye Webster", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/10/e1/3f/10e13f32-7d89-4092-ec35-fc6f6e19a291/656605041261.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/34/4d/19/344d197a-a550-963a-cf0b-e125f9be5992/mzaf_14334228675589876453.plus.aac.p.m4a"}'),
('bedroom', 1, '{"trackId": "1608931329", "trackName": "Bedroom Pop", "artistName": "Alexa Play", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/94/22/1d/94221db0-7b67-fe0b-0942-c92f7980e837/192641942563_Cover.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/2e/3d/2b/2e3d2b98-635d-b32f-a888-1db5533561fc/mzaf_4471451603333213887.plus.aac.p.m4a"}'),
('bedroom', 2, '{"trackId": "1420662243", "trackName": "Bedroom Pop", "artistName": "american poetry club", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/93/3f/95/933f9582-058c-e84b-d6ad-f211e7634c11/f6670bcc-706b-4c37-b7fe-83a158a245aa.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview128/v4/be/60/4a/be604a0c-818e-44cf-7e01-11bedb348119/mzaf_8350143455602764968.plus.aac.p.m4a"}'),
('bedroom', 3, '{"trackId": "1494865166", "trackName": "Bedroom Pop (feat. Claire Young)", "artistName": "Von Saxon", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/94/c8/38/94c83830-5f9b-3635-ae50-d39ec138f5a0/artwork.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/83/2b/3b/832b3b09-2329-4c39-1029-d7a5157d983c/mzaf_6636921979244102593.plus.aac.p.m4a"}'),
('dnb', 0, '{"trackId": "6783347751", "trackName": "Mums Voice", "artistName": "Liquid DnB", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/ac/7f/d9/ac7fd927-03a2-16dd-d78d-5fe7441ef1ea/artwork.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/b9/72/32/b972326a-d6c5-033e-b35c-6e73c272c59c/mzaf_7241996102279678205.plus.aac.p.m4a"}'),
('dnb', 1, '{"trackId": "6783347752", "trackName": "Buzz", "artistName": "Liquid DnB", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/ac/7f/d9/ac7fd927-03a2-16dd-d78d-5fe7441ef1ea/artwork.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/fc/36/3a/fc363afe-931c-3e75-2566-fb3997e19279/mzaf_10466442937936411307.plus.aac.p.m4a"}'),
('dnb', 2, '{"trackId": "6783347754", "trackName": "Sang It Wrong", "artistName": "Liquid DnB", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/ac/7f/d9/ac7fd927-03a2-16dd-d78d-5fe7441ef1ea/artwork.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/40/64/ac/4064ac22-589c-ca82-e9bd-6f4a66216323/mzaf_15762024409882700796.plus.aac.p.m4a"}'),
('dnb', 3, '{"trackId": "6783347756", "trackName": "Echo", "artistName": "Liquid DnB", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/ac/7f/d9/ac7fd927-03a2-16dd-d78d-5fe7441ef1ea/artwork.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/c5/81/f5/c581f50c-f741-f7ec-4079-80a887389c33/mzaf_2441904567731337737.plus.aac.p.m4a"}'),
('dnb', 4, '{"trackId": "6784254575", "trackName": "Pillow Talk", "artistName": "LiquidHour DnB", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/ac/20/dd/ac20dd2f-99e8-c293-9217-39c49e7ed408/artwork.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/95/62/bc/9562bcf9-c780-be20-8d75-2e5465c0d388/mzaf_2487284867060919533.plus.aac.p.m4a"}'),
('sadindie', 0, '{"trackId": "1512318907", "trackName": "I Know You", "artistName": "Faye Webster", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/10/e1/3f/10e13f32-7d89-4092-ec35-fc6f6e19a291/656605041261.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/34/4d/19/344d197a-a550-963a-cf0b-e125f9be5992/mzaf_14334228675589876453.plus.aac.p.m4a"}'),
('sadindie', 1, '{"trackId": "1786481197", "trackName": "back to friends", "artistName": "sombr", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/5d/d5/ad/5dd5ad1b-fabf-9218-77f0-3adbfd5328ac/054391237118.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/d7/63/7d/d7637dec-cf2d-1455-3398-f1a6340359d0/mzaf_88927986796632454.plus.aac.p.m4a"}'),
('sadindie', 2, '{"trackId": "1146195725", "trackName": "White Ferrari", "artistName": "Frank Ocean", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/bb/45/68/bb4568f3-68cd-619d-fbcb-4e179916545d/BlondCover-Final.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/86/5a/d1/865ad14f-f77e-3b9c-b108-930af566864d/mzaf_286153466120868843.plus.aac.p.m4a"}'),
('sadindie', 3, '{"trackId": "1604657975", "trackName": "ceilings", "artistName": "Lizzy McAlpine", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/11/6a/64/116a64ee-0db3-4e59-bd86-f44008e47f85/5056167170006.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/7b/52/b7/7b52b754-157a-6946-1a7f-3885d0d4b45f/mzaf_11031506980503485356.plus.aac.p.m4a"}'),
('sadindie', 4, '{"trackId": "1441416638", "trackName": "We Fell in Love in October", "artistName": "girl in red", "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/31/bd/f4/31bdf42e-33aa-7968-c345-d09428c14856/5054526166202.jpg/100x100bb.jpg", "previewUrl": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/9a/b8/7b/9ab87b47-d974-1ad9-74ac-cb4b13b1e5f6/mzaf_4557361008487214760.plus.aac.p.m4a"}');
