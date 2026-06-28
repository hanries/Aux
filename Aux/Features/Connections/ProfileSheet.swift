//
//  ProfileSheet.swift
//  Aux
//
//  Lightweight profile card: identity, DJ hot-rating, a few recent Hot picks, and
//  Follow / Message / Block. (Rich profiles are out of scope.)
//

import SwiftUI

@MainActor
@Observable
final class ProfileViewModel {
    let userID: String
    private(set) var card: ProfileCard?
    private(set) var loading = true
    private let service = ProfileService()

    init(userID: String) { self.userID = userID }

    func load() async {
        card = try? await service.card(userID: userID)
        loading = false
    }
}

struct ProfileSheet: View {
    let userID: String

    @State private var model: ProfileViewModel
    @State private var dmTarget: DMTarget?
    @State private var showBlockConfirm = false
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionsModel.self) private var connections
    private let dmService = DMService()

    init(userID: String) {
        self.userID = userID
        _model = State(initialValue: ProfileViewModel(userID: userID))
    }

    private var isMe: Bool { userID == connections.profile.id }

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                if let card = model.card {
                    content(card)
                } else if model.loading {
                    LoadingView(label: "Loading…")
                } else {
                    ErrorView(message: "Couldn't load that profile.")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .task { await model.load() }
        .sheet(item: $dmTarget) { target in
            NavigationStack {
                DMThreadView(
                    profile: connections.profile, dmID: target.dmID, otherID: target.otherID,
                    otherHandle: target.otherHandle, otherAvatar: target.otherAvatar)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func content(_ card: ProfileCard) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                AvatarView(emoji: card.profile.avatar, size: 88)
                Text(card.profile.handle).font(.title2.bold())
                if let rating = card.djRatingText {
                    Text(rating).font(.callout).foregroundStyle(.secondary)
                }

                if !isMe { actions(card) }

                if !card.recentHotPicks.isEmpty {
                    hotPicks(card.recentHotPicks)
                }

                if !isMe {
                    Button("Block @\(card.profile.handle)", role: .destructive) {
                        showBlockConfirm = true
                    }
                    .font(.footnote)
                    .padding(.top, 8)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Block @\(card.profile.handle)?",
                            isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { await connections.block(userID); dismiss() }
            }
        } message: {
            Text("They won't be able to message or follow you, and you'll stop seeing each other in taste twins.")
        }
    }

    private func actions(_ card: ProfileCard) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if connections.isFollowing(userID) { await connections.unfollow(userID) }
                    else { await connections.follow(userID) }
                }
            } label: {
                Label(connections.isFollowing(userID) ? "Following" : "Follow",
                      systemImage: connections.isFollowing(userID) ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(connections.isFollowing(userID) ? .gray : .accentColor)

            Button {
                Task {
                    guard let dmID = try? await dmService.openThread(with: userID) else { return }
                    dmTarget = DMTarget(
                        dmID: dmID, otherID: userID,
                        otherHandle: card.profile.handle, otherAvatar: card.profile.avatar)
                }
            } label: {
                Label("Message", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func hotPicks(_ tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent 🔥 picks").font(.headline)
            ForEach(tracks) { track in
                HStack(spacing: 10) {
                    AsyncImage(url: track.artworkURLSmall) { $0.resizable().scaledToFill() } placeholder: {
                        Color.white.opacity(0.08)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.trackName).font(.subheadline).lineLimit(1)
                        Text(track.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
