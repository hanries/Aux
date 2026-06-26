//
//  ServerClock.swift
//  Aux
//
//  Keeps a running estimate of the server's clock so every client computes the
//  same playback position. We periodically call the `server_now()` RPC and track
//  the offset between server time and this device's clock.
//
//  All synced timing (playback position, picking deadline) is expressed as a
//  `ServerTime` — an instant on the *server's* timeline — so device clock skew
//  never desyncs the room.
//

import Foundation
import Supabase
import PostgREST

/// An instant on the server's timeline, in epoch seconds.
struct ServerTime: Comparable {
    let epochSeconds: Double

    static func < (lhs: ServerTime, rhs: ServerTime) -> Bool {
        lhs.epochSeconds < rhs.epochSeconds
    }

    /// Seconds elapsed from `self` until `other` (negative if `other` is earlier).
    func seconds(until other: ServerTime) -> TimeInterval {
        other.epochSeconds - epochSeconds
    }
}

@Observable
@MainActor
final class ServerClock {
    /// serverEpoch − deviceEpoch, in seconds.
    private(set) var offset: TimeInterval = 0
    private(set) var isCalibrated = false

    private var timer: Task<Void, Never>?

    /// Best estimate of "now" on the server's timeline.
    var now: ServerTime {
        ServerTime(epochSeconds: Date().timeIntervalSince1970 + offset)
    }

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.calibrate()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func calibrate() async {
        do {
            let before = Date().timeIntervalSince1970
            let serverMs: Double = try await supabase.rpc("server_now").execute().value
            let after = Date().timeIntervalSince1970
            // Account for round-trip: assume the server read happened mid-flight.
            let deviceMid = (before + after) / 2
            offset = (serverMs / 1000) - deviceMid
            isCalibrated = true
        } catch {
            // Keep the last good offset; uncalibrated clients fall back to device time.
        }
    }
}
