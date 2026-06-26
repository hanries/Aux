//
//  AudienceView.swift
//  Aux
//
//  Who's in the room right now (Realtime presence).
//

import SwiftUI

struct AudienceView: View {
    let vm: RoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In the room (\(vm.audience.count))")
                .font(.headline)

            if vm.audience.isEmpty {
                Text("Just you, for now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(vm.audience) { member in
                            VStack(spacing: 4) {
                                AvatarView(
                                    emoji: member.avatar, size: 44,
                                    ring: member.userId == vm.profile.id ? .accentColor : nil)
                                Text(member.handle)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(maxWidth: 56)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
