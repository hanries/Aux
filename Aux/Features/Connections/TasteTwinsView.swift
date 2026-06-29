//
//  TasteTwinsView.swift
//  Aux
//
//  The room's "Taste twins" sheet — the people whose votes match yours this
//  session, with Follow + Message in one tap.
//

import SwiftUI

struct TasteTwinsView: View {
    let vm: RoomViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionsModel.self) private var connections
    @State private var profileTarget: UserRef?

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                if vm.tasteTwins.isEmpty {
                    ContentUnavailableView(
                        "No taste twins yet",
                        systemImage: "sparkles",
                        description: Text("Vote on a few tracks — the people who match you show up here."))
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(vm.tasteTwins) { twin in
                                TasteTwinCard(twin: twin) {
                                    profileTarget = UserRef(id: twin.otherId)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Taste twins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .task { await vm.refreshTasteTwins(force: true) }
        .sheet(item: $profileTarget) { ref in
            ProfileSheet(userID: ref.id).environment(connections)
        }
    }
}

struct TasteTwinCard: View {
    let twin: TasteTwin
    let onOpenProfile: () -> Void

    @Environment(ConnectionsModel.self) private var connections
    @State private var dmTarget: DMTarget?
    private let dmService = DMService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpenProfile) {
                HStack(spacing: 12) {
                    AvatarView(emoji: twin.avatar, size: 46, ring: .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(twin.handle).font(.headline)
                        Text("\(twin.shared) shared love\(twin.shared == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if !twin.sharedHotTracks.isEmpty {
                Text("🔥 you both loved: " +
                     twin.sharedHotTracks.prefix(3).map(\.trackName).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        if connections.isFollowing(twin.otherId) {
                            await connections.unfollow(twin.otherId)
                        } else {
                            await connections.follow(twin.otherId)
                        }
                    }
                } label: {
                    Label(connections.isFollowing(twin.otherId) ? "Following" : "Follow",
                          systemImage: connections.isFollowing(twin.otherId) ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(connections.isFollowing(twin.otherId) ? .gray : .accentColor)

                Button {
                    Task { await openDM() }
                } label: {
                    Label("Message", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(item: $dmTarget) { target in
            NavigationStack {
                DMThreadView(
                    profile: connections.profile, dmID: target.dmID, otherID: target.otherID,
                    otherHandle: target.otherHandle, otherAvatar: target.otherAvatar)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func openDM() async {
        guard let dmID = try? await dmService.openThread(with: twin.otherId) else { return }
        dmTarget = DMTarget(
            dmID: dmID, otherID: twin.otherId,
            otherHandle: twin.handle, otherAvatar: twin.avatar)
    }
}
