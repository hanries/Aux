//
//  CategoriesView.swift
//  Aux
//
//  Home → categories → rooms. Minimal/functional UI (visual design deferred to the
//  final redesign pass). Owns the Rooms-tab NavigationStack so "Join a room" can
//  push the routed instance programmatically.
//

import SwiftUI

struct CategoriesView: View {
    let profile: UserProfile

    @State private var model: CategoriesViewModel
    @State private var path = NavigationPath()

    init(profile: UserProfile) {
        self.profile = profile
        _model = State(initialValue: CategoriesViewModel(profile: profile))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                NightBackground()
                switch model.loadState {
                case .loading: LoadingView(label: "Finding rooms…")
                case .failed(let message): ErrorView(message: message) { Task { await model.start() } }
                case .ready: list
                }
            }
            .navigationTitle("Aux")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        AvatarView(emoji: profile.avatar, size: 28)
                        Text(profile.handle).font(.subheadline)
                    }
                }
            }
            .navigationDestination(for: Category.self) { category in
                CategoryView(category: category, model: model, profile: profile, path: $path)
            }
            .navigationDestination(for: Room.self) { room in
                RoomView(profile: profile, room: room)
            }
            .navigationDestination(for: RoomRef.self) { ref in
                RoomLoaderView(profile: profile, roomID: ref.id)
            }
        }
        .task { await model.start() }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Pick a category — rooms stay small, so they fill fast.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(model.categories) { category in
                    NavigationLink(value: category) { row(category) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func row(_ category: Category) -> some View {
        let theme = ThemeCatalog.theme(for: category.genre)
        let live = model.liveListeners(in: category.id)
        let rooms = model.liveRoomCount(in: category.id)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(theme.accent.opacity(0.18))
                Text(RoomConfig.genreEmoji(category.genre)).font(.system(size: 30))
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name).font(.headline)
                Text(live == 0 ? "quiet right now"
                     : "\(live) listening · \(rooms) live room\(rooms == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct CategoryView: View {
    let category: Category
    let model: CategoriesViewModel
    let profile: UserProfile
    @Binding var path: NavigationPath

    @State private var joining = false

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(spacing: 14) {
                    joinButton

                    let instances = model.rooms(in: category.id).filter { model.isLive($0) }
                    if instances.isEmpty {
                        Text("No live rooms yet — tap Join to start one.")
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        Text("Live rooms").font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(instances) { room in
                            NavigationLink(value: room) { instanceRow(room) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var joinButton: some View {
        Button {
            Task {
                joining = true
                if let id = await model.join(category) { path.append(RoomRef(id: id)) }
                joining = false
            }
        } label: {
            HStack(spacing: 8) {
                if joining { ProgressView() } else { Image(systemName: "bolt.fill") }
                Text("Join a room")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(ThemeCatalog.theme(for: category.genre).accent)
        .disabled(joining)
    }

    private func instanceRow(_ room: Room) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).font(.subheadline.weight(.semibold))
                if room.phase == .playing, let track = room.currentTrack {
                    Text("♪ \(track.trackName) — \(model.djName(room) ?? "Auto-DJ")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("warming up").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("\(model.listeners(room))").font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
