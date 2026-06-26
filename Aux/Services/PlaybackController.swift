//
//  PlaybackController.swift
//  Aux
//
//  Timestamp-driven playback. Given the room's current track + server-time start,
//  it seeks AVPlayer to `serverNow − playbackStartedAt` so every client lands on
//  roughly the same spot (±1–2s). A ticker keeps the UI position live and nudges
//  the player back when it drifts.
//

import AVFoundation
import Foundation

@MainActor
@Observable
final class PlaybackController {

    /// 0...clipDuration, for the now-playing progress UI.
    private(set) var positionSeconds: Double = 0
    /// True while a clip is actively playing (vs reveal gap / picking / idle).
    private(set) var isPlaying = false

    private let player = AVPlayer()
    private weak var clock: ServerClock?
    private var room: Room?

    private var loadedRoundID: String?
    private var loadedURL: URL?
    private var ticker: Task<Void, Never>?

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    func attach(clock: ServerClock) {
        self.clock = clock
    }

    func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.reconcile()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func update(room: Room) {
        self.room = room
        reconcile()
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedRoundID = nil
        loadedURL = nil
        isPlaying = false
    }

    /// Decide what the player should be doing right now.
    private func reconcile() {
        guard let room, let clock else { return }

        guard room.phase == .playing,
              let track = room.currentTrack,
              let url = track.previewURL,
              let startedAt = room.playbackStartedAt,
              let roundID = room.roundId
        else {
            // picking / idle / no track → silence (reveal or waiting).
            pauseForGap()
            return
        }

        let position = startedAt.seconds(until: clock.now)

        if position < 0 {
            pauseForGap()
            return
        }
        if position >= RoomConfig.clipDuration {
            // Clip ended; hold on the reveal until the room advances.
            positionSeconds = RoomConfig.clipDuration
            if isPlaying { player.pause(); isPlaying = false }
            return
        }

        if loadedRoundID != roundID {
            if loadedURL != url {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                loadedURL = url
            }
            loadedRoundID = roundID
            seek(to: position)
            player.play()
            isPlaying = true
        } else {
            let current = player.currentTime().seconds
            if current.isFinite, abs(current - position) > RoomConfig.driftTolerance {
                seek(to: position)
            }
            if player.timeControlStatus != .playing {
                player.play()
            }
            isPlaying = true
        }
        positionSeconds = min(position, RoomConfig.clipDuration)
    }

    private func pauseForGap() {
        if isPlaying { player.pause(); isPlaying = false }
        positionSeconds = 0
    }

    private func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}
