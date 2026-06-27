# Aux 🎧

A real-time, room-based social music game for iOS. Drop into a genre room, take turns at a **Turntable-style rotating DJ booth** — one DJ plays a 30-second clip for the room, everyone votes **hot** or **skip**, and the reveal shows *who voted what*. The real product is connection between strangers: the people whose taste matches yours become the friends you keep coming back for.

> Synced listening is the substrate, not the pitch. Jam, SharePlay, and Discord Listen Along already do synced audio — but only with friends you already have, and none of them have a DJ game. The wedge is the part they won't build: **strangers + a game + a community.**

## Status

| Milestone | Scope | State |
|-----------|-------|-------|
| **M1** | The room loop: one seeded room, presence, rotating DJ booth, synced 30s playback, hot/skip voting, reveal (who voted what), DJ hot-rating, realtime chat, auto-DJ fallback | ✅ Done |
| **M2** | Breadth + room states: 6 live rooms, an active-first lobby with realtime counts, clean join/leave/switch + background lifecycle, role/phase UI polish, per-room independent loops, leader-driven advancement | ✅ Done |
| **M3** | The connection layer: taste twins → follow → 1:1 DM *(the moat)* | ⬜ Planned |
| **M4** | Ship: report/block, polish, TestFlight | ⬜ Planned |

## Features (today)

- **Lobby** — six always-on genre rooms (2am Lo-Fi, Hyperpop, 2000s Throwbacks, Bedroom Pop, Drum & Bass, Sad Girl Indie), sorted active-first, with live "X listening", on-deck DJ + current track, and lineup length.
- **Rotating DJ booth** — step up to the decks, cue a pick via iTunes search; the baton rotates each round. Roles are legible: on deck, in line (with your position — "you're #2" — and cued track), or audience.
- **Synced playback** — every client computes its position from a server timestamp and seeks `AVPlayer` there (±1–2s). A built-in **auto-DJ** keeps a room playing when the lineup is empty, so it's never silent.
- **Vote → reveal** — a voting countdown, then the tally **plus who voted what**, then a "rotating to @next" beat.
- **Realtime chat** and live **presence** (the audience).
- **Anonymous auth** — pick a handle + emoji avatar and you're in.

## Tech

- **Client:** SwiftUI, iOS 17+, Swift `async/await`, Observation (`@Observable`), AVFoundation.
- **Backend / realtime:** [Supabase](https://supabase.com) (Postgres + Realtime + Auth) via [`supabase-swift`](https://github.com/supabase/supabase-swift).
- **Music:** the free [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/) — 30-second `previewUrl` clips, no key, no label deals, no geo-restrictions. (Deliberately **not** Spotify, whose preview API was closed to new apps.)
- **Serverless rotation:** a per-room **leader client** (the on-deck DJ, or the longest-present member) calls an idempotent `advance_room()` Postgres function, guarded by a compare-and-swap on `round_id`. No always-on app server, no Edge Functions, no cron — SQL only.

## Getting started

### Prerequisites
- Xcode 16+ and an iOS 17+ simulator or device
- A free [Supabase](https://supabase.com) project

### 1. Set up Supabase
1. In the Supabase **SQL Editor**, run [`supabase/schema.sql`](supabase/schema.sql), then [`supabase/milestone2.sql`](supabase/milestone2.sql). This creates the tables, RLS policies, RPCs, the realtime publication, and seeds the 6 rooms + their auto-DJ playlists.
2. **Authentication → Providers → enable "Allow anonymous sign-ins".**

### 2. Add your credentials
```bash
cp Secrets.example.swift Aux/Config/Secrets.swift
```
Open `Aux/Config/Secrets.swift` and paste your **Project URL** and **anon / publishable key** (Project Settings → API). The file is gitignored — your keys never get committed. Until it's filled in, the app shows a friendly "configure Supabase" screen.

### 3. Build & run
```bash
xcodebuild -project Aux.xcodeproj -scheme Aux \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
…or just open `Aux.xcodeproj` and hit ▶. Run on **two** simulators/devices to feel the multiplayer loop.

## Project structure

```
Aux/
  App/        AuxApp (entry), RootView (router), AppSession (auth/profile gate)
  Config/     Secrets.swift (gitignored), SupabaseClientProvider (global `supabase`)
  Models/     Track, Room, LineupEntry, Vote, ChatMessage, UserProfile, PresenceMember
  Services/   Auth/Room/Lineup/Vote/Chat services (REST); RoomChannel + LobbyChannel
              (realtime); PlaybackController (AVPlayer sync); RoomEngine (advance loop +
              heartbeat); ServerClock (server-time offset); ITunesSearchService
  Features/   Onboarding/, Lobby/, Room/ (RoomViewModel = the brain + subviews),
              Search/, Chat/
  Shared/     RoomConfig, SharedViews
supabase/     schema.sql (M1), milestone2.sql (M2)
```

`CLAUDE.md` has the deeper architecture notes — the sync/rotation model, the lobby's denormalized live counts, leader election, and the join/leave/background lifecycle.

## How it stays in sync (the short version)

The `rooms` row is the source of truth: `phase`, `current_dj_id`, `current_track`, `playback_started_ms`, `round_id`. Clients calibrate a server-time offset, compute `position = serverNow − playback_started`, and seek the player there. The room's leader advances the round when the clip + reveal window closes (idempotent CAS RPC, with a non-leader failsafe), and writes a lightweight audience heartbeat so the lobby's "X listening" stays live and self-heals empty rooms.

## License

Personal project / work in progress. Music previews are served by Apple's iTunes Search API; Aux stores and streams nothing itself.
