//
//  ReactionViews.swift
//  Aux
//
//  The reaction palette (the primary action), the live attributed overlay, the
//  in-moment taste spark, and the "waved at you" toast.
//

import SwiftUI

/// The bottom palette. `love` doubles as the taste signal and highlights when set.
struct ReactionBarView: View {
    let vm: RoomViewModel
    @Environment(\.roomTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ReactionType.palette) { type in
                Button {
                    Task { await vm.react(type) }
                } label: {
                    Text(type.emoji)
                        .font(.system(size: 26))
                        .frame(width: 52, height: 52)
                        .background(
                            Circle().fill(
                                type == .love && vm.iLoveCurrent
                                    ? AnyShapeStyle(theme.loveAccent.opacity(0.35))
                                    : AnyShapeStyle(.ultraThinMaterial)))
                }
                .buttonStyle(.plain)
                .disabled(vm.onDeckTrack == nil)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .opacity(vm.onDeckTrack == nil ? 0.5 : 1)
    }
}

/// A light "live pulse" — the most recent attributed reactions, fading in.
struct ReactionOverlay: View {
    let vm: RoomViewModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(vm.recentReactions.suffix(6)) { reaction in
                let info = vm.displayMember(reaction.userId)
                HStack(spacing: 4) {
                    Text(info.avatar).font(.caption)
                    Text(reaction.type.emoji).font(.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: vm.recentReactions.count)
        .allowsHitTesting(false)
    }
}

/// The in-moment connection spark when you and a stranger both loved a track.
struct TasteSparkView: View {
    let spark: RoomViewModel.Spark
    let onWave: () -> Void
    let onMessage: () -> Void
    let onDismiss: () -> Void
    @Environment(\.roomTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(emoji: spark.avatar, size: 36, ring: theme.loveAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("✨ you & @\(spark.handle) both love this")
                    .font(.caption.weight(.semibold))
                Text("say hi while it's playing").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: onWave) { Image(systemName: "hand.wave.fill") }.buttonStyle(.bordered)
            Button(action: onMessage) { Image(systemName: "paperplane.fill") }.buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.loveAccent.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 12)
        .onTapGesture(perform: onDismiss)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
