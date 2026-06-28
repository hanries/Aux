//
//  PeopleView.swift
//  Aux
//
//  Following + followers. The retention hook: followed users who are live right
//  now, with a tap to jump into their room.
//

import SwiftUI

struct PeopleView: View {
    let profile: UserProfile

    @Environment(ConnectionsModel.self) private var connections
    @State private var profileTarget: UserRef?

    private var liveFollowing: [FollowUser] { connections.following.filter(\.isLive) }

    var body: some View {
        ZStack {
            NightBackground()
            if connections.following.isEmpty && connections.followers.isEmpty {
                ContentUnavailableView(
                    "No people yet",
                    systemImage: "person.2",
                    description: Text("Follow your taste twins from a room — they show up here, and you'll see when they're live."))
            } else {
                list
            }
        }
        .navigationTitle("People")
        .task {
            await connections.refreshAll()
            connections.clearFollowerBadge()
        }
        .sheet(item: $profileTarget) { ref in
            ProfileSheet(userID: ref.id).environment(connections)
        }
    }

    private var list: some View {
        List {
            if !liveFollowing.isEmpty {
                Section("Live now") {
                    ForEach(liveFollowing) { friend in
                        NavigationLink(value: RoomRef(id: friend.roomId ?? "")) {
                            personRow(avatar: friend.avatar, handle: friend.handle,
                                      subtitle: "live in \(friend.roomName ?? "a room")",
                                      live: true)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                }
            }
            Section("Following") {
                ForEach(connections.following) { friend in
                    Button { profileTarget = UserRef(id: friend.userId) } label: {
                        personRow(avatar: friend.avatar, handle: friend.handle,
                                  subtitle: friend.isLive ? "live in \(friend.roomName ?? "a room")" : "offline",
                                  live: friend.isLive)
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }
            if !connections.followers.isEmpty {
                Section("Followers") {
                    ForEach(connections.followers) { follower in
                        HStack {
                            Button { profileTarget = UserRef(id: follower.userId) } label: {
                                personRow(avatar: follower.avatar, handle: follower.handle,
                                          subtitle: follower.iFollowBack ? "you follow each other" : "follows you",
                                          live: false)
                            }
                            Spacer()
                            if !follower.iFollowBack {
                                Button("Follow back") {
                                    Task { await connections.follow(follower.userId) }
                                }
                                .font(.caption).buttonStyle(.borderedProminent)
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func personRow(avatar: String, handle: String, subtitle: String, live: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(emoji: avatar, size: 40, ring: live ? .green : nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(handle).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption)
                    .foregroundStyle(live ? .green : .secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
