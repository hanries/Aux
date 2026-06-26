//
//  DJBoothView.swift
//  Aux
//
//  The rotation: who's on deck, who's waiting (and whether they've cued), plus
//  step-up / step-down / cue controls.
//

import SwiftUI

struct DJBoothView: View {
    let vm: RoomViewModel
    let onCue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The Booth")
                .font(.headline)

            onDeckRow

            if !vm.waitingLineup.isEmpty {
                Text("Next up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(vm.waitingLineup) { entry in
                    lineupRow(entry)
                }
            }

            controls
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var onDeckRow: some View {
        HStack(spacing: 10) {
            AvatarView(emoji: vm.onDeckAvatar, size: 40, ring: .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.onDeckName).font(.subheadline.weight(.semibold))
                Text("spinning now").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("▶︎").foregroundStyle(.tint)
        }
    }

    private func lineupRow(_ entry: LineupEntry) -> some View {
        let info = vm.displayMember(entry.userId)
        return HStack(spacing: 10) {
            AvatarView(emoji: info.avatar, size: 32)
            Text(info.handle).font(.subheadline)
            Spacer()
            Text(entry.hasCued ? "cued ✓" : "no pick yet")
                .font(.caption)
                .foregroundStyle(entry.hasCued ? .green : .secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if vm.amInLineup {
            if let cued = vm.myCuedTrack {
                Text("Your cue: \(cued.trackName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Button(vm.myCuedTrack == nil ? "Cue a track" : "Change pick", action: onCue)
                    .buttonStyle(.borderedProminent)
                Button("Step down", role: .destructive) {
                    Task { await vm.stepDown() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        } else {
            Button {
                Task { await vm.stepUp() }
            } label: {
                Label("Step up to DJ", systemImage: "music.mic")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
