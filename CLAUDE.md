# CLAUDE.md — Aux

Context for future Claude Code sessions. Read `aux-mvp.md` for the full product spec.

## What this is

**Aux** is a real-time, **people-first** social music game. You drop into a small genre
room, see the **crowd** of faces (the hero), and **react** to the same music together —
a live, *attributed* emote palette (fire/hands/laugh/wave/love). A single DJ holds the
decks for a **set** of 30s clips by **possession** (keeps them by default; passes only on
leave / idle / sustained-cold). **No hot/skip vote, no reveal phase, no per-track
rotation** — those were the pre-rebuild model. The real product is *connection between
strangers*: **love-reaction overlap = taste twins** → follow → DM.

> The room model was **rebuilt** (see `aux-mvp.md` "Build sequence (revised)"). M1–M3
> below describe the *original* Turntable voting build; the rebuild replaced the room
> engine + screen with the people-first/reactions/possession model. Plumbing (Supabase
> services, realtime, presence, clip-sync, the follow/DM/block layer) was reused.

## Milestone status

- **M1 (done): the room loop.** One seeded room ("2am Lo-Fi"), presence, rotating DJ
  booth with per-DJ cued picks, synced 30s playback, hot/skip voting, reveal (who voted
  what), DJ hot-rating, realtime chat, auto-DJ fallback. Anonymous auth.
- **M2 (done): breadth + room states.** 6 seeded rooms, a live lobby (active-first,
  realtime counts/now-playing/lineup), clean join/leave/switch + background lifecycle,
  role/phase UI polish (on deck / in line "#2" / audience, voting countdown, reveal,
  "rotating to @next"), per-room independent loops, leader-driven advancement.
- **M3 (done): the connection layer** — taste twins (vote-overlap RPC) surfaced in a room
  sheet + a rate-limited reveal nudge; follow + "your people are live" (jump to their room);
  realtime 1:1 DMs with an inbox + unread; lightweight profile cards; block (the safety
  floor). App is now a Rooms / People / Messages TabView.
- **M4 (not built): ship** — report + moderation, push, polish, TestFlight.

### Rebuild (current model — supersedes the M1–M3 room game)

- **Phase 1 (done): people-first room engine.** Crowd-as-hero (`CrowdView`), the DJ on
  stage (`DJStageView`), the live attributed reaction palette (`ReactionBarView` +
  `ReactionViews`) with the directed **wave** + in-moment **taste sparks**, **set**-based
  **possession** tenure (one DJ, no rotation), auto-DJ, chat. `reactions` table replaces
  `votes`; `advance_set` + `cue_set` replace `advance_room`/`cue_track`; `taste_twins` now
  = love-reaction overlap. SQL: `supabase/rebuild.sql`. (`votes`/`advance_room` left dormant.)
- **Phase 2 (done): theme system.** `Theme` tokens + `ThemeCatalog` (warm/neon/retro)
  keyed off genre, injected via `@Environment(\.roomTheme)`; `ThemedBackground` (gradient +
  ambient motion) in the room; lobby/room views read tokens. Look varies, engine doesn't.
- **Phase 3 (done): categories + room instancing + a 7-person cap.** Home → categories → rooms.
  `categories` table (one per genre); `rooms.category_id`/`instance_no`; `join_category()`
  RPC routes to the fullest active instance under cap, reuses an idle one, else spins up
  "<Category> N". SQL: `supabase/phase3.sql`. Rooms tab = `CategoriesView` → `CategoryView`
  (flat `LobbyView` retired). **UI is intentionally minimal — final redesign pass deferred.**
- **Phase 4 (effectively done via the rebuild): connection layer** — taste twins from
  love-reaction overlap, follow, "your people are live", 1:1 DM, block (built in M3, rewired
  to reactions). Lives in the People / Messages tabs + the room taste-twins sheet.
- **Phase 5 (not built): ship** (report/moderation, polish, TestFlight) + the **UI redesign
  pass** (all visual design saved for then).

## Stack & locked decisions (don't re-litigate)

- **SwiftUI, iOS 17+** (project deployment target is 26.x), Swift, async/await,
  **Observation** (`@Observable`) for view models. AVFoundation/AVPlayer for clips.
- **Music:** iTunes Search API (free, no key), 30s `previewUrl` clips. **Not Spotify.**
- **Backend/realtime:** Supabase (Postgres + Realtime + Auth) via `supabase-swift`
  (SPM, pinned `>= 2.0.0`, resolves to 2.48.x).
- **Auth:** Supabase **anonymous sign-in** + a `users` row (handle + emoji avatar).
- **Play model (rebuild):** one DJ holds the decks for a **set** by **possession**
  (no rotation, no vote); audience action is **reactions**, not hot/skip.
- **Advance:** leader client (on-deck DJ, else longest-present) → idempotent `advance_set()`
  RPC (CAS on `round_id`): pops the DJ's `cued_set` head; passes the decks only on
  leave / idle-grace / sustained-cold (reaction floor). Fully serverless — SQL only.

## Project layout

```
Aux/
  App/        AuxApp (entry), RootView (router), AppSession (auth/profile gate)
  Config/     Secrets.swift (GITIGNORED), SupabaseClientProvider (global `supabase`)
  Models/     Track, Room, LineupEntry, Vote, ChatMessage, UserProfile, PresenceMember
  Services/   AuthService, RoomService, LineupService, VoteService, ChatService (REST);
              RoomChannel (one realtime channel: room/lineup/votes/messages + presence
              + host election); PlaybackController (AVPlayer sync); RoomEngine (advance
              loop); ServerClock (server-time offset); ITunesSearchService; RealtimeDecode
  Features/   Onboarding/, Lobby/, Room/ (RoomViewModel = the brain + subviews), Search/,
              Chat/, Connections/ (ConnectionsModel + TasteTwins/Profile/People/Inbox/DMThread)
  App/        + MainTabView (Rooms/People/Messages)
  Shared/     RoomConfig (constants + genreEmoji), SharedViews (Avatar/Loading/Error/Night)
supabase/schema.sql       # M1: full schema + RLS + RPCs + realtime + seed (run first)
supabase/milestone2.sql   # M2: live-lobby columns + room_heartbeat + 5 more rooms (run 2nd)
supabase/milestone3.sql   # M3: follows/blocks/dms + taste_twins/DM/presence RPCs (run 3rd)
Secrets.example.swift  # repo-root template → copy to Aux/Config/Secrets.swift
```

`RoomViewModel` owns the engines/services and exposes derived state; views are thin and
read from it. Chat state lives on `RoomViewModel` (no separate ChatViewModel).

## How sync + rotation works

- The `rooms` row is the source of truth: `phase` (`idle|playing|picking`),
  `current_dj_id` (null ⇒ auto-DJ), `current_track` jsonb, `playback_started_ms`,
  `phase_deadline_ms`, `round_id`. Time math uses the **epoch-ms** columns (the
  timestamptz columns are ignored on the client to dodge Postgres date parsing).
- `ServerClock` calibrates an offset via the `server_now()` RPC; clients compute
  `position = serverNow − playback_started`. `PlaybackController` seeks AVPlayer there
  and re-seeks on >1.5s drift. ±1–2s sync is fine.
- `RoomChannel` keeps presence (the audience). Host = earliest joiner present. `RoomEngine`
  (host, with a non-host failsafe) calls `advance_room(room, expectedRound, presentIDs)`
  when the clip+reveal window closes / the pick timer expires / the room is stale.
- `advance_room` (SECURITY DEFINER, CAS on `round_id`): sends finished DJ to the back,
  picks the lowest-position **present** DJ; plays their cued track, or enters `picking`
  if they have none, or auto-DJs from `default_tracks` if the lineup is empty.
- All room/lineup mutations go through RPCs (`step_up`, `step_down`, `cue_track`,
  `advance_room`); clients only directly write `votes` and `messages` (RLS-guarded to
  `auth.uid()`). Votes are unique per `(round_id, voter_id)`; reveal reads votes by round.

## Lobby + multi-room (M2)

- **Routing:** `RootView` → `NavigationStack { LobbyView }` with
  `navigationDestination(for: Room.self) { RoomView(profile:, room:) }`. `RoomViewModel`
  is parameterized by `roomID` + an initial `Room` snapshot; `RoomConfig.roomID` is now
  just the M1 seed reference.
- **Live lobby counts are denormalized onto `rooms`:** `audience_count` +
  `audience_heartbeat_ms` (written by the room **leader** via the `room_heartbeat` RPC on
  presence change and every ~8s) and `lineup_count` (kept fresh by `step_up`/`step_down`/
  `advance_room`). `LobbyChannel` is one realtime subscription to the whole `rooms` table;
  `LobbyViewModel` sorts active-first and treats a stale heartbeat (> `lobbyStaleAfter`,
  ~18s) as idle/0 — so empty rooms self-heal with no final-0 write needed.
- **Leader election (per room, deterministic):** the on-deck DJ's client if present, else
  the longest-present member (`RoomChannel.longestPresentID`). The leader drives
  `advance_room` (still CAS on `round_id`) **and** the heartbeat; non-leaders keep the M1
  failsafe grace. If the DJ leaves mid-round, leadership falls to the longest-present
  client. A client only ever runs one room's `RoomEngine`; rooms advance independently
  because each is driven by its own occupants.
- **Lifecycle:** each `RoomView` owns a fresh `RoomViewModel` per `room.id`; `.onDisappear`
  → `vm.stop()` tears down channel (unsubscribe drops presence) + engine + playback +
  timers. The **shared `ServerClock.shared`** survives switches (no re-calibration).
  `scenePhase` → `enterBackground()` (untrack presence + `playback.suspend()` + engine
  stop) / `enterForeground()` (recalibrate, retrack, refetch room, resume).

## Connection layer (M3)

- **Routing is now a TabView** (`MainTabView`): Rooms (lobby→room), People (following +
  live), Messages (DM inbox), with badges for new followers + unread DMs. An app-scoped
  `ConnectionsModel` (`@Observable`, injected via `.environment`) owns blocked-set,
  following/followers, DM threads + unread, the new-follower badge, and the realtime subs
  (`dms` + `follows`, RLS-scoped to me) + a 12s poll. **Sheets re-inject
  `.environment(connections)`** since sheet env propagation isn't guaranteed.
- **Taste twins** = the `taste_twins(p_room_id, min, recency)` RPC over `votes`
  (`agreement = agree/shared`, excludes blocked pairs, returns `shared_hot_tracks`). Scoring
  is never client-side. `votes.track` (jsonb, set on cast) gives the "you both loved" names.
  `RoomViewModel` fetches on reveal (debounced) + on opening the sheet, and shows a
  rate-limited reveal nudge (once per person).
- **"Your people are live"** = denormalized `users.current_room_id` + `presence_heartbeat_ms`,
  written by every client via `set_presence` on join/leave/background + a 10s heartbeat;
  `my_following`/`live_followees` treat a stale heartbeat as offline. (Realtime presence is
  still the per-room audience.)
- **Follow / DM / block** all go through SECURITY DEFINER RPCs (`follow_user`,
  `find_or_create_dm`, `send_dm`, `mark_dm_read`, `block_user`, …). `dms` use a sorted
  (`user_lo<user_hi`) pair for find-or-create; unread = `last_ms > my read_ms`. **Block is
  mutual + server-enforced** for taste-twins/DM/follow (the RPCs see all blocks); the
  audience also hides blocked users client-side.
- **RLS** on `follows`/`blocks`/`dms`/`dm_messages` so you only read your own relationships
  and threads. New realtime tables: `dms`, `dm_messages`, `follows`.

## Conventions

- `@Observable` + `@MainActor` view models; `Codable` structs; thin service layer.
- **No force-unwraps** in app logic (config literals excepted). Handle loading/empty/error.
- **All user ids are lowercased** client-side to match Postgres uuid text (so string
  comparisons against `current_dj_id` / `voter_id` line up).
- Secrets never committed: real creds in gitignored `Aux/Config/Secrets.swift`.

## Build gotchas (already handled — keep them)

- The Xcode project uses **synchronized file groups** (objectVersion 77): any `.swift`
  under `Aux/` is auto-included. Don't hand-add source files to `pbxproj`.
- `SWIFT_APPROACHABLE_CONCURRENCY` is set to **NO** for the Aux target: leaving it `YES`
  crashed the compiler ("failed to produce diagnostic") on the `SupabaseClient` init.
- `MEMBER_IMPORT_VISIBILITY` is on, so the umbrella `import Supabase` is **not** enough —
  import the submodule that defines what you call: `PostgREST` (`.from/.rpc/.execute/
  .value`), `Auth` (sign-in), `Realtime` (channels/presence/`*Action` types).
- `Secrets.example.swift` lives at the **repo root**, not under `Aux/`, so it isn't
  compiled (two `enum Secrets` would collide).
- The global `supabase` client is `nonisolated(unsafe)` (project defaults to MainActor
  isolation; the client is `Sendable`).

## Run / test

See `README` section in the final setup message, or:
1. `schema.sql`, `milestone2.sql`, `milestone3.sql`, `rebuild.sql`, `phase3.sql` in order.
2. Supabase → Auth → enable **anonymous sign-ins**.
3. `cp Secrets.example.swift Aux/Config/Secrets.swift` and paste URL + anon key.
4. Build/run on two simulators; verify: lobby lists 6 rooms (active-first, live counts),
   join/leave/switch with no leaked audio, auto-DJ audio, step up → cue → synced play,
   vote + reveal (who voted what) + "rotating to @next", baton rotation, chat, and that
   advancement continues when the on-deck DJ (leader) leaves mid-round.

Build from CLI:
`xcodebuild -project Aux.xcodeproj -scheme Aux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
