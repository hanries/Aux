# Aux — Spec & Room Model

*Working codename "Aux" (as in passing the aux cord). Final name TBD. This document is the single source of truth; the milestone prompts derive from it.*

---

## One-liner

A place to meet people through a live music game. Drop into a small genre room (~20 people), see everyone, react to the same music together, and the people whose taste matches yours become the friends you keep coming back for.

---

## What this is — and what it deliberately isn't

- **It is** a real-time, small-room social music game whose *actual product is connection between strangers*. The people are the interface; the music is the shared object in the middle.
- **It is not a dating app.** Romance can be an outcome; the framing is meeting people broadly (friends, crews, scenes).
- **It is not "Spotify Jam as a standalone app."** Synced listening is the substrate, not the pitch. Jam, Apple SharePlay, and Discord Listen Along all do synced listening — but only **with friends you already have**, and none of them put you in a room of strangers reacting to each other. The wedge is the part none of them will build: **meeting strangers + a DJ game + a community.**

---

## Why this can work where the whole category died

Turntable.fm — the closest ancestor — died of two things, even after a $7.5M-funded pandemic revival. This is designed to dodge both:

1. **Music licensing economics.** Turntable burned >25% of capital on royalties and couldn't license internationally. **Dodge:** we never stream full or licensed tracks — only free 30-second preview clips (iTunes Search API). No label deals, no Premium, no geo-limits.
2. **Novelty decay.** Turntable was "a game, and like most games, eventually it's not [fun]," and listening is mostly passive. **Dodge:** the connection layer is the antidote — relationships don't expire when novelty does. If rooms produce real friends and recurring crews, retention survives past the point the game gets old.

---

## THE ROOM MODEL (the heart)

### Two principles

- **People are the interface, not the player.** You see ~20 faces, react to each other, and acknowledge each other. The now-playing is legible but not the hero.
- **One room engine, many skins.** Every room runs the *identical* interaction model; only the *theme* changes by category. Users never relearn a room.

### Room size: ~20 people

Capped at ~20 so faces stay individually real and the room feels intimate and *full fast* — which directly eases cold-start (a room feels alive at 8, not 800). Popularity creates **more rooms** (instanced per category), never bigger ones: when a room fills, newcomers route to the next instance ("Lo-Fi 2").

### Navigation: Home → categories → rooms

Home leads to **categories** (genres/moods). Each category holds a set of live rooms you can enter. Categories are three things at once: the browse structure, the cold-start funnel (steer people into active, near-full rooms), and the anchor for each room's aesthetic.

### The people-first room screen

- **The crowd** — everyone in the room as faces/avatars, the visible hero. Never a bare "X listening" count.
- **The DJ on stage** — the current DJ spotlighted as a *person* (avatar, handle), visibly playing for the room.
- **Now playing, clearly** — track + artist + artwork get a clean, persistent home tied to the DJ. Legible, not buried. (People are the hero *and* the song is readable — both are true.)
- **Attributed live reactions** — reactions show *who* sent them, and when someone reacts at you, you see it ("@x waved at you"). Being seen, not counted.
- **Acknowledge gestures** — tap anyone to wave / quick-react: catching someone's eye across the room.
- **Live taste sparks** — when you and a stranger react the same way (a "love"), a connection spark surfaces in the moment with a one-tap wave / say-hi.
- **Chat** — realtime room chat.

### Reactions (the primary action)

The audience's main moment-to-moment action is **reacting**, from a palette of quick emotes — e.g. fire, hands-up, laughing, the directed **wave**, plus a **love/save** ("this is my taste"). Reactions pull **triple duty**:

1. The **live social pulse** of the room.
2. The **taste-twin signal** — *love/save overlap = taste twins.* (This replaces the old hot-vote signal; it's richer and stays positive.)
3. In aggregate, the **warmth that keeps a DJ on the decks** (see tenure).

There is **no hot/skip vote** and **no "skip this track" button.** Clips are ~30 seconds — a bad one is over before a skip would matter (Turntable's Lame-skip existed for full-length songs). The only negative signal is the *absence* of warmth, which feeds the vibe meter passively.

### The DJ: stepping up, sets, and possession-based tenure

- **Stepping up** is first-come — step up to an open slot; you cue a track to take the decks. A lineup forms when slots are contested.
- **Sets, not single tracks** — a DJ holds the decks for a *set* (a run of 30s clips they cue) while the audience reacts continuously. No per-track rotation.
- **Possession-based tenure (no vote)** — the DJ holds the decks **by default**. There is **no keep/pass vote and no eviction button** — the room's reactions *are* the verdict, passively. The decks pass to the next person in line only when the DJ (a) leaves, (b) goes idle, or (c) the room stays **cold** across several tracks (reactions persistently low — a passive vibe floor).
- **Why this** — it mirrors what actually made Turntable addictive (you hold a contested spot by playing well) while avoiding the griefing failure mode of letting a handful of people in a 20-person room vote someone out. Being a good DJ means you *held the decks through a long set because the room loved you* — earned status, and the retention meta-game.
- **DJ standing** — a DJ accrues warmth/standing from reactions to their picks (seed of the meta-game; ranks/leaderboards deferred).
- **Auto-DJ fallback** — if no one is on the decks, the room auto-plays from a default genre playlist so it is **never silent**.

### Per-room aesthetics (theming)

- Each category/room has its own **theme**: palette, type, background, emote style, ambient motion (Lo-Fi = warm and dim; Hyperpop = loud and neon).
- **The rule:** vary the *theme*, never the *interaction model*. Build it as a **theme-token system** — a room's look is config, not bespoke code.
- **Ship 2–3 themes first**, not eight. Themes are a layer on the one room engine.

### The connection layer (the moat)

- **Taste twins** = users whose **love/save reactions overlap** most with yours this session (minimum-overlap threshold; computed server-side). Surfaced live (in-moment sparks) and in a "taste twins" panel.
- **Follow** — plus the retention hook: see which people you follow are **live right now**, with one tap to **jump into their room** ("your people are live").
- **1:1 DM** + an inbox.
- **Block** — the safety floor for stranger DMs. Report + broader moderation come later.

---

## Technical architecture

- **Client:** SwiftUI, iOS 17+, async/await. AVFoundation / AVPlayer for clip playback.
- **Music data:** iTunes Search API (free, no key) → `previewUrl` (~30s `.m4a`) + metadata; Deezer fallback. **Not Spotify** — its preview API was removed for new apps in Nov 2024.
- **Backend + realtime:** Supabase (Postgres + Realtime + Auth) via `supabase-swift`.
- **Sync model:** the `rooms` row holds `current_dj_id`, `current_track` (JSON), and `playback_started_at` (server timestamp). Clients seek `AVPlayer` to `now − playback_started_at` and play the 30s clip. When a clip ends, the next clip in the on-deck DJ's set plays — advanced by a **per-room leader client (the on-deck DJ)** via an optimistic/conditional write, with handoff to the next eligible client if the DJ drops. Possession rules govern DJ changes. Reactions, chat, and presence run over Realtime.
- **The room engine** is a *clip player + live reaction stream + possession monitor* (it replaces the old phased vote/reveal engine). The active **theme** is injected as tokens.

### Data model (sketch)

- `users` (id, handle, avatar_url)
- `categories` (id, name, theme_key)
- `rooms` (id, category_id, name, instance_no, current_dj_id, current_track, playback_started_at)
- `dj_lineup` (room_id, user_id, position, cued_track)
- `reactions` (id, room_id, track_id, dj_id, user_id, type ∈ {fire, hands, laugh, wave, love}, target_user_id?, created_at)
- `messages` (room chat); `dms` / `dm_messages`; `follows`; `blocks`
- Audience presence is ephemeral via Realtime.
- Taste twins = love-reaction overlap query (RLS-protected DMs/follows/blocks). DJ warmth = reaction tally on a DJ's picks. Room "cold" = reaction rate below a floor across N tracks.

### Deferred (fast-follows, not now)

Full-track / Premium playback · user-created and private rooms · multiple simultaneous DJ decks (MVP is one on-deck DJ) · deep gamification (points economy, ranks, leaderboards, unlockable avatars) · weekly recap / Wrapped · the "predict the room" prediction mini-game · rich profiles, discovery, friends-of-friends · push notifications · web version.

---

## Risks & mitigations

- **Licensing** → 30-second preview clips; no deals, no Premium.
- **Novelty decay / retention** → the connection layer (taste twins, follows, recurring rooms).
- **Cold-start / liquidity** → small ~20 rooms that feel full fast; auto-DJ fallback so rooms are never silent; categories as a funnel into active rooms; instancing instead of empty mega-rooms.
- **Platform absorption** → strangers + DJ game + connection (the part Jam/SharePlay won't build).
- **DJ griefing** → possession, not an eviction vote; tenure ends only via leave / idle / sustained-cold floor.
- **Safety / moderation** → block from day one; report + moderation tooling later; consider trust gating before scaling.

---

## Success metrics

1. **Participation** — do people react, step up to DJ, and stay for a full session?
2. **Connection (the key one)** — do people follow or DM a taste twin?
3. **Retention** — do they come back when their people are live? (The exact test Turntable failed.)

---

## Monetization (later, not now)

Defer entirely. Eventually: cosmetic / DJ status, premium or private rooms, host tools. Nothing that taxes the core experience.

---

## Build sequence (revised)

1. **Room engine (one theme).** The people-first room, end to end: ~20-cap visible crowd, the DJ on stage with possession-based tenure, synced 30s clip *sets*, the reaction palette (live + attributed) plus the wave gesture, now-playing clearly placed, the auto-DJ fallback, and chat — in a single theme, on Supabase Realtime with lightweight auth.
2. **Theme system + category skins.** The theme-token system, plus 2–3 category aesthetics riding on the one engine.
3. **Categories + room instancing + cap.** Home → categories → rooms; instanced rooms per category; the ~20 cap with overflow routing to new instances.
4. **Connection layer.** Taste twins from love-reaction overlap → follow → "your people are live" → 1:1 DM → block (with RLS).
5. **Ship.** Report + moderation, a polish pass, TestFlight into one niche community.
