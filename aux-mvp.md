# Aux — MVP Specification

*Working codename "Aux" (as in passing the aux cord). Final name TBD.*

---

## One-liner

A place to meet people through a live music game. Step up to the decks in a genre room, play a 30-second clip for the room, everyone votes it **hot** or **skip** — and the people whose taste matches yours become the friends you keep coming back for.

---

## What this is — and what it deliberately isn't

- **It is** a real-time, room-based social music game whose *actual product is connection between strangers*.
- **It is not a dating app.** Romance can be an outcome, but the framing and the MVP are about meeting people broadly (friends, crews, scenes). Dating is the hardest possible market and we're not anchoring to it.
- **It is not "Spotify Jam as a standalone app."** Jam is one collaborative queue everyone dumps tracks into — no performer, no stakes. We are explicitly *not* that. We use a Turntable-style **rotating DJ booth**: one person performs a pick for the room at a time, and the room reacts to *their* taste. Jam, Apple SharePlay, and Discord Listen Along all already do synced listening — but only **with friends you already have**, and none of them have a DJ game. Our defensible wedge is the part none of them will build: **meeting strangers + a DJ game + a community.**

---

## Why this can work where the whole category died

Turntable.fm — the closest ancestor — died of two things, and even a $7.5M-funded pandemic-era revival couldn't escape niche. This MVP is designed to dodge both causes of death:

1. **Music licensing economics.** Turntable burned >25% of its capital on royalties and couldn't license internationally. **Our dodge:** we never stream full or licensed tracks. We use free 30-second preview clips (iTunes Search API). No label deals, no Spotify Premium requirement, no geo-restrictions.
2. **Novelty decay.** Turntable was "a game, and like most games, eventually it's not [fun]," and music listening is mostly passive. **Our dodge:** the connection layer is the antidote. Relationships don't expire when the novelty does. If rooms produce real friends and recurring crews, retention survives past the point where the DJ game itself gets old. *This is why the connection layer is the whole point, not a feature.*

---

## The core loop

**The round (the engagement engine):**
step up to the decks → the on-deck DJ plays their cued pick as a 30-second clip, synced across everyone → the room votes hot or skip → results reveal *who voted what* → the baton rotates to the next DJ.

**The branch that matters (the product):**
at the reveal, vote overlap surfaces your **taste twins** (the people who voted like you) → one tap to follow or DM → recurring crews and friendships.

The reveal must show **individual** votes, not just an aggregate — "who's the monster who skipped this banger?" is the banter that creates connection. The DJ game is the icebreaker engine; the people it reveals are the product.

---

## MVP scope

### In scope

- Lightweight auth: anonymous handle + avatar, or Sign in with Apple (pick the simplest path).
- ~4–6 pre-seeded, always-on genre rooms (e.g. *2am Lo-Fi*, *Hyperpop*, *2000s Throwbacks*, *Bedroom Pop*, *Drum & Bass*, *Sad Girl Indie*). No user-created rooms yet.
- Live presence in a room (who's in the audience right now).
- **Rotating DJ booth:**
  - Users can **step up to the decks** to join the DJ lineup, or stay in the audience.
  - **One DJ on at a time.** While waiting in the lineup, a DJ cues up a next pick via iTunes search (one cued-track slot per DJ). When their turn comes, that pick auto-plays.
  - On clip end (or when a short voting window closes), the **baton rotates** to the next DJ in the lineup; the previous DJ moves to the back.
  - If a DJ's turn arrives with nothing cued, they get a brief window to pick; if they don't, the baton passes.
  - **Auto-DJ fallback:** if the lineup is empty, the room plays from a built-in default genre playlist so it is **never silent**.
- Synced 30-second clip playback of the on-deck pick, coordinated by a server timestamp.
- Vote hot/skip per track (one vote per user per track).
- Reveal: tally + who voted what.
- **DJ hot-rating:** a DJ accumulates a simple rating from how the room votes their picks (seed of the meta-game; ranks/leaderboards deferred).
- Realtime room chat.
- **Taste twins:** after a few tracks, surface the users whose votes overlap most with yours this session; follow + start a 1:1 DM.
- Basic 1:1 DM.
- Report / block (minimal safety baseline).

### Explicitly out of scope (fast-follows, not now)

- Full-track / Spotify Premium playback.
- User-created and private rooms.
- Multiple simultaneous DJ decks (Turntable had up to 5) — MVP is a single on-deck DJ.
- Deep gamification: DJ points economy, ranks, unlockable avatars, leaderboards. (The basic hot-rating above stays in.)
- Weekly recap / Wrapped.
- The "predict how the room will vote" prediction mini-game.
- Rich profiles, discovery, friends-of-friends.
- Push notifications (beyond, optionally, DMs).
- Web version.

---

## Technical architecture

- **Client:** SwiftUI, iOS 17+ (target latest), Swift with async/await. **AVFoundation / AVPlayer** for clip playback.
- **Music data:** **iTunes Search API** — free, no API key. `https://itunes.apple.com/search?term={q}&entity=song&limit=25` returns `previewUrl` (a ~30s `.m4a`), `trackName`, `artistName`, `artworkUrl100`, `trackId`. Deezer API is a fallback. **Do not use Spotify previews** — `preview_url` was removed for new apps in Nov 2024.
- **Backend + realtime:** **Supabase** (Postgres + Realtime + Auth), via the `supabase-swift` SDK. *Firebase Realtime Database is an equally valid alternative* if you prefer its presence/disconnect handling; Supabase is recommended because Postgres makes the vote-overlap / taste-twin queries clean.

### Sync model

The `rooms` row holds `current_dj_id`, `current_track` (JSON), and `playback_started_at` (server timestamp). When the on-deck DJ's pick starts, the server writes those fields; each client computes `position = now − playback_started_at` and seeks `AVPlayer` to it, playing the 30-second clip. When a clip ends, the server rotates the DJ lineup, sets the next `current_dj_id` + `current_track` + `playback_started_at`, and clients react via realtime subscription. Clip brevity bounds the drift, so "good enough" sync (±1–2s) is fine — this is a party, not a precision DJ set.

### Data model (sketch)

- `users` (id, handle, avatar_url, created_at)
- `rooms` (id, name, genre, current_dj_id, current_track, playback_started_at)
- `dj_lineup` (room_id, user_id, position, cued_track JSON) — the ordered DJ rotation + each waiting DJ's next pick
- `votes` (id, room_id, track_id, dj_id, voter_id, vote ∈ {hot, skip}, created_at) — attributed to the DJ's pick, which powers the DJ hot-rating
- `messages` (id, room_id, user_id, text, created_at)
- `dms` / `dm_messages` (1:1 threads)
- `follows` (follower_id, followee_id)
- Audience presence is ephemeral via Supabase Realtime presence.

Taste-twin score = vote-overlap between two users across the tracks they both voted on this session (compute in a query; no separate table needed for MVP). DJ hot-rating = hot-vote share across a DJ's picks (also a query).

---

## Risks & mitigations

- **Licensing** → 30-second preview clips; no deals, no Premium. *(Neutralizes Turntable's #1 killer.)*
- **Novelty decay / retention** → the connection layer (taste twins, follows, recurring rooms). *(Neutralizes Turntable's #2 killer.)*
- **Cold-start / liquidity** → rooms, not forced 1:1; seed always-on rooms; auto-DJ fallback so a room is never empty/silent; launch into one niche community first rather than broadly.
- **Platform absorption** → differentiate on the part Jam/SharePlay won't build: strangers + DJ game + connection.
- **Safety / moderation** → report and block from day one; consider trust gating (e.g. an invite or campus gate) before scaling.

---

## Success metrics (what the MVP must prove)

1. **Participation:** do people step up to DJ, vote, and chat — and stay for a full session?
2. **The key one — connection:** do people follow or DM a taste twin? This is the signal that the moat works.
3. **Retention:** do they come back the next day / week? This is the exact test Turntable failed.

---

## Monetization (later, not MVP)

Defer entirely. Eventually: cosmetic / DJ status, premium or private rooms, host tools. Nothing that taxes the core experience.

---

## Build sequence

1. **Milestone 1 — the room loop.** One seeded room, end to end: step up to the decks → cue/pick a track (iTunes search) → synced 30s clip → vote → reveal → baton rotates → chat, on Supabase Realtime with lightweight auth, plus the auto-DJ fallback. *(This is what the Claude Code prompt targets.)*
2. **Milestone 2 — breadth.** Multiple seeded rooms, presence polish, audience/DJ UI states.
3. **Milestone 3 — the connection layer.** Taste twins → follow → 1:1 DM. *(The moat. Do not skip.)*
4. **Milestone 4 — ship.** Report/block, polish, TestFlight with a single niche community.
