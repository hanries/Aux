//
//  CrowdView.swift
//  Aux
//
//  The hero: everyone in the room as faces. Tap a face to wave / catch their eye;
//  long-press to open their profile. People are the interface.
//

import SwiftUI

struct CrowdView: View {
    let vm: RoomViewModel
    let onWave: (String) -> Void
    let onProfile: (String) -> Void
    @Environment(\.roomTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In the room · \(vm.audience.count)")
                .font(.headline)

            if vm.audience.isEmpty {
                Text("Just you, for now — wave someone in.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(vm.audience) { member in
                        face(member)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func face(_ member: PresenceMember) -> some View {
        let isMe = member.userId == vm.profile.id
        let isDJ = member.userId == vm.room?.currentDjId
        return VStack(spacing: 4) {
            AvatarView(emoji: member.avatar, size: 52,
                       ring: isDJ ? theme.djAccent : (isMe ? theme.accent : nil))
            Text(isMe ? "you" : member.handle)
                .font(.caption2).lineLimit(1).frame(maxWidth: 64)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isMe { onWave(member.userId) } }
        .onLongPressGesture { if !isMe { onProfile(member.userId) } }
    }
}
