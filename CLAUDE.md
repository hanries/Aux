# CLAUDE.md — Aux

Context for future Claude Code sessions. Read `aux-mvp.md` for the full product spec.

## What this is

**Aux** is a real-time, room-based social music game. Players drop into a genre room
and take turns at a **Turntable-style rotating DJ booth**: one on-deck DJ plays a 30s
clip for the room, everyone votes **hot/skip**, the reveal shows **who voted what**, and
the baton rotates to the next DJ. The real product is *connection between strangers* —
the people whose taste matches yours become friends. That connection layer (taste twins
→ follow → DM) is a **later milestone**; this repo currently implements **Milestone 1**:
the synced DJ-booth loop in a single seeded room.

## Milestone status

- **M1 (done): the room loop.** One seeded room ("2am Lo-Fi"), presence, rotating DJ
  booth with per-DJ cued picks, synced 30s playback, hot/skip voting, reveal (who voted
  what), DJ hot-rating, realtime chat, auto-DJ fallback. Anonymous auth.
- **M2 (not built): breadth** — multiple seeded rooms, presence/UI polish.
- **M3 (not built): the connection layer** — taste twins → follow → 1:1 DM. *The moat.*
- **M4 (not built): ship** — report/block, polish, TestFlight.

Leave clean extension points for M2–M4; don't build them unless asked.

## Stack & locked decisions (don't re-litigate)

- **SwiftUI, iOS 17+** (project deployment target is 26.x), Swift, async/await,
  **Observation** (`@Observable`) for view models. AVFoundation/AVPlayer for clips.
- **Music:** iTunes Search API (free, no key), 30s `previewUrl` clips. **Not Spotify.**
- **Backend/realtime:** Supabase (Postgres + Realtime + Auth) via `supabase-swift`
  (SPM, pinned `>= 2.0.0`, resolves to 2.48.x).
- **Auth:** Supabase **anonymous sign-in** + a `users` row (handle + emoji avatar).
- **Play model:** rotating DJ booth (single on-deck DJ), **not** a shared queue.
- **Queue advance:** host-elected client → idempotent `advance_room()` RPC (CAS on
  `round_id`). Fully serverless — SQL only, no Edge Functions / cron.

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
  Features/   Onboarding/, Room/ (RoomViewModel = the brain + NowPlaying/DJBooth/
              Audience/VotePanel/Reveal subviews), Search/, Chat/
  Shared/     RoomConfig (constants), SharedViews (Avatar/Loading/Error/NightBackground)
supabase/schema.sql    # full schema + RLS + RPCs + realtime + seed (run in SQL editor)
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
1. `supabase/schema.sql` in the Supabase SQL editor.
2. Supabase → Auth → enable **anonymous sign-ins**.
3. `cp Secrets.example.swift Aux/Config/Secrets.swift` and paste URL + anon key.
4. Build/run on two simulators; verify: presence, auto-DJ audio, step up → cue → synced
   play, vote + reveal (who voted what), baton rotation, picking countdown, chat.

Build from CLI:
`xcodebuild -project Aux.xcodeproj -scheme Aux -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
