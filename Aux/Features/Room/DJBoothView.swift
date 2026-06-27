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
            HStack {
                Text("The Booth").font(.headline)
                Spacer()
                roleBadge
            }

            onDeckRow

            if !vm.waitingLineup.isEmpty {
                Text("Up next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(vm.waitingLineup.enumerated()), id: \.element.id) { index, entry in
                    lineupRow(entry, position: index + 1)
                }
            }

            controls
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var roleBadge: some View {
        let (text, color): (String, Color) = switch vm.myRole {
        case .onDeck: ("you're on deck", .pink)
        case .inLine: (vm.myLinePosition.map { "you're #\($0)" } ?? "in line", .accentColor)
        case .audience: ("audience", .secondary)
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
    }

    private var onDeckRow: some View {
        HStack(spacing: 10) {
            AvatarView(emoji: vm.onDeckAvatar, size: 40, ring: .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.onDeckName).font(.subheadline.weight(.semibold))
                if let next = vm.upNextName {
                    Text("spinning now · up next: \(next)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("spinning now").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("▶︎").foregroundStyle(.tint)
        }
    }

    private func lineupRow(_ entry: LineupEntry, position: Int) -> some View {
        let info = vm.displayMember(entry.userId)
        let isMe = entry.userId == vm.profile.id
        return HStack(spacing: 10) {
            Text("\(position)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            AvatarView(emoji: info.avatar, size: 32)
            Text(isMe ? "\(info.handle) (you)" : info.handle)
                .font(.subheadline)
                .fontWeight(isMe ? .semibold : .regular)
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
