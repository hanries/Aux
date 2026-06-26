//
//  Room.swift
//  Aux
//
//  The synced source of truth. We only decode the epoch-ms time columns
//  (`*_ms`) for sync math — the timestamptz columns are ignored on the client to
//  avoid Postgres date-format parsing. Unknown keys are skipped by the decoder.
//

import Foundation

struct Room: Codable, Identifiable {
    let id: String
    let name: String
    let genre: String
    let phase: Phase
    let currentDjId: String?
    let currentTrack: Track?
    let playbackStartedMs: Double?
    let phaseDeadlineMs: Double?
    let roundId: String?

    enum Phase: String, Codable {
        case idle, playing, picking
    }

    enum CodingKeys: String, CodingKey {
        case id, name, genre, phase
        case currentDjId = "current_dj_id"
        case currentTrack = "current_track"
        case playbackStartedMs = "playback_started_ms"
        case phaseDeadlineMs = "phase_deadline_ms"
        case roundId = "round_id"
    }

    /// Playback start as a wall-clock-agnostic server instant (seconds).
    var playbackStartedAt: ServerTime? {
        playbackStartedMs.map { ServerTime(epochSeconds: $0 / 1000) }
    }

    var phaseDeadline: ServerTime? {
        phaseDeadlineMs.map { ServerTime(epochSeconds: $0 / 1000) }
    }

    var isAutoDJ: Bool { currentDjId == nil }
}
