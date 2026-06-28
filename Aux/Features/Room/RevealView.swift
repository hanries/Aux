//
//  RevealView.swift
//  Aux
//
//  The payoff: the tally AND who voted what. Individual votes are the whole
//  point — they're the banter that turns strangers into taste twins later.
//

import SwiftUI

struct RevealView: View {
    let vm: RoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let nudge = vm.nudgeText { tasteTwinNudge(nudge) }
            tallyBar
            Divider().overlay(.white.opacity(0.1))
            whoVotedWhat
            rotatingFooter
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func tasteTwinNudge(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text("✨").font(.callout)
            Text(text).font(.caption.weight(.medium))
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var rotatingFooter: some View {
        Divider().overlay(.white.opacity(0.1))
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("rotating to \(vm.upNextName ?? "Auto-DJ")…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack {
            Text("The verdict")
                .font(.headline)
            Spacer()
            Text("🔥 \(vm.hotCount)   ⏭️ \(vm.skipCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var tallyBar: some View {
        GeometryReader { geo in
            let total = max(1, vm.hotCount + vm.skipCount)
            let hotWidth = geo.size.width * CGFloat(vm.hotCount) / CGFloat(total)
            HStack(spacing: 0) {
                Rectangle().fill(.pink).frame(width: hotWidth)
                Rectangle().fill(.gray.opacity(0.5))
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    @ViewBuilder
    private var whoVotedWhat: some View {
        if vm.revealRows.isEmpty {
            Text("No votes this round.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(vm.revealRows, id: \.member.id) { row in
                    HStack(spacing: 10) {
                        AvatarView(emoji: row.member.avatar, size: 32)
                        Text(row.member.handle).font(.subheadline)
                        Spacer()
                        Text(row.vote == .hot ? "🔥 Hot" : "⏭️ Skip")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                (row.vote == .hot ? Color.pink : Color.gray).opacity(0.25),
                                in: Capsule())
                    }
                }
            }
        }
    }
}
