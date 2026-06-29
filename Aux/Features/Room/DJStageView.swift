//
//  DJStageView.swift
//  Aux
//
//  The DJ on stage as a *person*, with now-playing tied to them — legible, but
//  not the hero (the crowd is).
//

import SwiftUI

struct DJStageView: View {
    let vm: RoomViewModel
    @Environment(\.roomTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            artwork
            djRow
            if vm.roundStage == .playing {
                progressBar
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.black.opacity(0.25))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 200)
            .overlay {
                if let url = vm.onDeckTrack?.artworkURLLarge {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                        ProgressView()
                    }
                } else {
                    Text(vm.onDeckTrack == nil ? "🎧" : "🎵").font(.system(size: 56))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var djRow: some View {
        HStack(spacing: 12) {
            AvatarView(emoji: vm.onDeckAvatar, size: 44, ring: theme.djAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.onDeckName).font(.system(.headline, design: theme.fontDesign))
                if let track = vm.onDeckTrack {
                    Text("\(track.trackName) — \(track.artistName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if vm.roundStage == .picking {
                    Text("lining up a track…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("on the decks").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.djWarmth > 0 {
                Text("💜 \(vm.djWarmth)").font(.subheadline.weight(.semibold))
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: vm.progress).tint(theme.djAccent)
            HStack {
                Text(time(vm.playback.positionSeconds))
                Spacer()
                Text("0:30")
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func time(_ s: Double) -> String {
        String(format: "0:%02d", min(max(0, Int(s)), 30))
    }
}
