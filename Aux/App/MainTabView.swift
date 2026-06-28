//
//  MainTabView.swift
//  Aux
//
//  The signed-in shell: Rooms / People / Messages, with badges for new followers
//  and unread DMs. The app-scoped ConnectionsModel is injected via @Environment so
//  follow/block/DM actions work from cards everywhere.
//

import SwiftUI

/// A room referenced only by id (e.g. jumping to a live friend's room).
struct RoomRef: Hashable { let id: String }

struct MainTabView: View {
    let profile: UserProfile

    @State private var connections: ConnectionsModel

    init(profile: UserProfile) {
        self.profile = profile
        _connections = State(initialValue: ConnectionsModel(profile: profile))
    }

    var body: some View {
        TabView {
            NavigationStack {
                LobbyView(profile: profile)
                    .navigationDestination(for: Room.self) { room in
                        RoomView(profile: profile, room: room)
                    }
            }
            .tabItem { Label("Rooms", systemImage: "music.note.house.fill") }

            NavigationStack {
                PeopleView(profile: profile)
                    .navigationDestination(for: RoomRef.self) { ref in
                        RoomLoaderView(profile: profile, roomID: ref.id)
                    }
            }
            .tabItem { Label("People", systemImage: "person.2.fill") }
            .badge(connections.newFollowerBadge)

            NavigationStack {
                InboxView(profile: profile)
                    .navigationDestination(for: DMThread.self) { thread in
                        DMThreadView(
                            profile: profile, dmID: thread.dmId, otherID: thread.otherId,
                            otherHandle: thread.otherHandle, otherAvatar: thread.otherAvatar)
                    }
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }
            .badge(connections.unreadCount)
        }
        .environment(connections)
        .task { await connections.start() }
    }
}

/// Fetches a Room by id, then shows it — used when jumping into a friend's room.
struct RoomLoaderView: View {
    let profile: UserProfile
    let roomID: String

    @State private var room: Room?
    @State private var failed = false

    var body: some View {
        Group {
            if let room {
                RoomView(profile: profile, room: room)
            } else if failed {
                ErrorView(message: "Couldn't open that room.")
            } else {
                LoadingView(label: "Opening room…")
            }
        }
        .task {
            do { room = try await RoomService().fetchRoom(id: roomID) }
            catch { failed = true }
        }
    }
}
