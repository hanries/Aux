//
//  RoomEngine.swift
//  Aux
//
//  Drives the rotation. The host (earliest joiner present) calls `advance_room`
//  when the current clip's voting/reveal window closes, when a picking DJ's timer
//  runs out, or to bootstrap a stale/empty room. Non-hosts run the same checks on
//  a delay as a self-healing failsafe — the RPC is idempotent (compare-and-swap on
//  round_id), so redundant calls are harmless no-ops.
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
    var isHost: () -> Bool = { false }
    var presentIDs: () -> [String] = { [] }

    /// Extra grace before a non-host steps in if the host stalls.
    private let failsafeGrace: TimeInterval = 3

    init(roomID: String) {
        self.roomID = roomID
    }

    func start(clock: ServerClock) {
        self.clock = clock
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickIfDue()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tickIfDue() async {
        guard let clock, clock.isCalibrated, !inFlight else { return }
        guard let room = currentRoom() else { return }
        guard let due = dueTime(for: room, now: clock.now) else { return }

        let elapsed = due.seconds(until: clock.now)
        guard elapsed >= 0 else { return }

        let grace = isHost() ? 0 : failsafeGrace
        guard elapsed >= grace else { return }

        inFlight = true
        defer { inFlight = false }
        do {
            try await supabase.rpc("advance_room", params: AdvanceParams(
                p_room_id: roomID,
                p_expected_round_id: room.roundId,
                p_present: presentIDs()
            )).execute()
        } catch {
            // Swallow; next tick retries. CAS keeps this safe.
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
}
