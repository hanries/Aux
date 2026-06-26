//
//  VotePanelView.swift
//  Aux
//
//  Hot / Skip while the clip is playing. The breakdown stays hidden until the
//  reveal — only a running count of how many have voted is shown.
//

import SwiftUI

struct VotePanelView: View {
    let vm: RoomViewModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                voteButton(.hot, label: "Hot", emoji: "🔥", tint: .pink)
                voteButton(.skip, label: "Skip", emoji: "⏭️", tint: .gray)
            }
            Text("\(vm.hotCount + vm.skipCount) in the room voted")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func voteButton(_ kind: VoteKind, label: String, emoji: String, tint: Color) -> some View {
        let selected = vm.myVote == kind
        return Button {
            Task { await vm.vote(kind) }
        } label: {
            VStack(spacing: 6) {
                Text(emoji).font(.system(size: 34))
                Text(label).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? tint.opacity(0.35) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? tint : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!vm.canVote)
        .opacity(vm.canVote ? 1 : 0.5)
    }
}
