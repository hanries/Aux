//
//  DJBoothView.swift
//  Aux
//
//  The line + your controls: step up, build your set, step down. The DJ holds the
//  decks by possession (no rotation) — the line is who's next when a seat opens.
//

import SwiftUI

struct DJBoothView: View {
    let vm: RoomViewModel
    let onCue: () -> Void
    @Environment(\.roomTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("The Booth").font(.headline)
                Spacer()
                roleBadge
            }

            if !vm.waitingLineup.isEmpty {
                Text("In line").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
        case .onDeck: ("on the decks", theme.djAccent)
        case .inLine: (vm.myLinePosition.map { "you're #\($0)" } ?? "in line", theme.accent)
        case .audience: ("audience", .secondary)
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
    }

    private func lineupRow(_ entry: LineupEntry, position: Int) -> some View {
        let info = vm.displayMember(entry.userId)
        let isMe = entry.userId == vm.profile.id
        return HStack(spacing: 10) {
            Text("\(position)").font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary).frame(width: 16)
            AvatarView(emoji: info.avatar, size: 32)
            Text(isMe ? "\(info.handle) (you)" : info.handle)
                .font(.subheadline).fontWeight(isMe ? .semibold : .regular)
            Spacer()
            Text(entry.set.isEmpty ? "no set yet" : "\(entry.set.count) cued")
                .font(.caption).foregroundStyle(entry.set.isEmpty ? Color.secondary : Color.green)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if vm.amInLineup {
            if !vm.myCuedSet.isEmpty {
                Text("Your set: \(vm.myCuedSet.count) queued — next: \(vm.myCuedSet.first?.trackName ?? "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 12) {
                Button("Add to set", action: onCue).buttonStyle(.borderedProminent)
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
                Label("Step up to DJ", systemImage: "music.mic").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
}
