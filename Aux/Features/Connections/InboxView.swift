//
//  InboxView.swift
//  Aux
//
//  DM inbox — threads with last message + an unread dot. Tap to open the thread.
//

import SwiftUI

struct InboxView: View {
    let profile: UserProfile

    @Environment(ConnectionsModel.self) private var connections

    var body: some View {
        ZStack {
            NightBackground()
            if connections.threads.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Message a taste twin from a room to start a conversation."))
            } else {
                List(connections.threads) { thread in
                    NavigationLink(value: thread) { row(thread) }
                        .listRowBackground(Color.white.opacity(0.04))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Messages")
        .task { await connections.refreshThreads() }
    }

    private func row(_ thread: DMThread) -> some View {
        HStack(spacing: 12) {
            AvatarView(emoji: thread.otherAvatar, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.otherHandle).font(.subheadline.weight(.semibold))
                Text(thread.lastText ?? "Say hi 👋")
                    .font(.caption)
                    .foregroundStyle(thread.unread ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if thread.unread {
                Circle().fill(Color.accentColor).frame(width: 9, height: 9)
            }
        }
        .padding(.vertical, 4)
    }
}
