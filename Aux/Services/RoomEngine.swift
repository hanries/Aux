//
//  RoomEngine.swift
//  Aux
//
//  Drives the rotation + the lobby heartbeat for one room. The leader (the on-deck
//  DJ's client, or the longest-present member for auto-DJ rounds / if the DJ left)
//  calls `advance_room` when the clip+reveal window closes, when a picking timer
//  runs out, or to bootstrap a stale room, and writes the audience heartbeat.
//  Non-leaders run the same advance checks on a delay as a self-healing failsafe —
//  the RPC is idempotent (compare-and-swap on round_id), so redundant calls no-op.
//

import Foundation
import Supabase

@MainActor
final class RoomEngine {

    private let roomID: String
    private weak var clock: ServerClock?
    private var task: Task<Void, Never>?
    private var inFlight = false

    /// Wired by RoomViewModel so the engine always reads live state.
    var currentRoom: () -> Room? = { nil }
    var isLeader: () -> Bool = { false }
    var presentIDs: () -> [String] = { [] }

    /// Extra grace before a non-leader steps in if the leader stalls.
    private let failsafeGrace: TimeInterval = 3

    private var lastHeartbeatAt: ServerTime?
    private var lastHeartbeatCount = -1

    init(roomID: String) {
        self.roomID = roomID
    }

    func start(clock: ServerClock) {
        self.clock = clock
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickIfDue()
                await self?.tickHeartbeat()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        lastHeartbeatAt = nil
        lastHeartbeatCount = -1
    }

    private func tickIfDue() async {
        guard let clock, clock.isCalibrated, !inFlight else { return }
        guard let room = currentRoom() else { return }
        guard let due = dueTime(for: room, now: clock.now) else { return }

        let elapsed = due.seconds(until: clock.now)
        guard elapsed >= 0 else { return }

        let grace = isLeader() ? 0 : failsafeGrace
        guard elapsed >= grace else { return }

        inFlight = true
        defer { inFlight = false }
        do {
            try await supabase.rpc("advance_set", params: AdvanceParams(
                p_room_id: roomID,
                p_expected_round_id: room.roundId,
                p_present: presentIDs()
            )).execute()
        } catch {
            // Swallow; next tick retries. CAS keeps this safe.
        }
    }

    /// The leader keeps the room's lobby heartbeat fresh — on count change and at
    /// least every `heartbeatInterval`, so the lobby shows accurate "X listening".
    private func tickHeartbeat() async {
        guard let clock, isLeader() else { return }
        let count = presentIDs().count
        let stale = lastHeartbeatAt.map {
            $0.seconds(until: clock.now) >= RoomConfig.heartbeatInterval
        } ?? true
        guard count != lastHeartbeatCount || stale else { return }
        do {
            try await supabase.rpc("room_heartbeat", params: HeartbeatParams(
                p_room_id: roomID, p_count: count)).execute()
            lastHeartbeatCount = count
            lastHeartbeatAt = clock.now
        } catch {
            // Best-effort; retried next tick.
        }
    }

    /// When the room should next advance, on the server's timeline.
    private func dueTime(for room: Room, now: ServerTime) -> ServerTime? {
        // No round yet → bootstrap immediately.
        if room.roundId == nil { return now }

        switch room.phase {
        case .playing:
            guard let started = room.playbackStartedAt else { return now }
            return ServerTime(
                epochSeconds: started.epochSeconds + RoomConfig.clipDuration + RoomConfig.revealWindow
            )
        case .picking:
            return room.phaseDeadline ?? now
        case .idle:
            return now
        }
    }
}

// MARK: - RPC params

struct AdvanceParams: Encodable {
    let p_room_id: String
    let p_expected_round_id: String?
    let p_present: [String]

    enum CodingKeys: String, CodingKey {
        case p_room_id, p_expected_round_id, p_present
    }

    // The default synthesized encoder OMITS a nil optional, which makes PostgREST
    // look for a 2-arg overload of advance_room (which doesn't exist). We must
    // always send `p_expected_round_id`, as JSON null on the bootstrap round.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_room_id, forKey: .p_room_id)
        if let round = p_expected_round_id {
            try c.encode(round, forKey: .p_expected_round_id)
        } else {
            try c.encodeNil(forKey: .p_expected_round_id)
        }
        try c.encode(p_present, forKey: .p_present)
    }
}

struct HeartbeatParams: Encodable {
    let p_room_id: String
    let p_count: Int
}
