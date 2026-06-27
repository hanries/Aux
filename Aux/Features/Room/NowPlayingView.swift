//
//  NowPlayingView.swift
//  Aux
//
//  Artwork, track, who's on deck, and the synced progress bar.
//

import SwiftUI

struct NowPlayingView: View {
    let vm: RoomViewModel

    var body: some View {
        VStack(spacing: 16) {
            artwork
            trackInfo
            onDeck
            progressBar
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.black.opacity(0.25))
            if let url = vm.onDeckTrack?.artworkURLLarge {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Text(vm.onDeckTrack == nil ? "⏳" : "🎵")
                    .font(.system(size: 64))
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(vm.onDeckTrack?.trackName ?? "Waiting for the next pick")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(vm.onDeckTrack?.artistName ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var onDeck: some View {
        HStack(spacing: 10) {
            AvatarView(emoji: vm.onDeckAvatar, size: 36, ring: .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.onDeckName).font(.subheadline.weight(.semibold))
                Text(vm.djHotRatingText ?? "on the decks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isLeader {
                Text("LEADER")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.25), in: Capsule())
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: vm.progress)
                .tint(.accentColor)
            HStack {
                Text(timeString(vm.playback.positionSeconds))
                Spacer()
                if let left = vm.votingSecondsLeft {
                    Text("\(left)s left")
                        .foregroundStyle(left <= 5 ? .orange : .secondary)
                }
                Spacer()
                Text("0:30")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "0:%02d", min(s, 30))
    }
}
