//
//  LobbyView.swift
//  Aux
//
//  Home screen: the live list of genre rooms. Tap one to join.
//

import SwiftUI

struct LobbyView: View {
    let profile: UserProfile

    @State private var vm: LobbyViewModel

    init(profile: UserProfile) {
        self.profile = profile
        _vm = State(initialValue: LobbyViewModel(profile: profile))
    }

    var body: some View {
        ZStack {
            NightBackground()
            switch vm.loadState {
            case .loading:
                LoadingView(label: "Finding rooms…")
            case .failed(let message):
                ErrorView(message: message) { Task { await vm.start() } }
            case .ready:
                list
            }
        }
        .navigationTitle("Aux")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    AvatarView(emoji: profile.avatar, size: 28)
                    Text(profile.handle).font(.subheadline)
                }
            }
        }
        .task { await vm.start() }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Pick a room. Someone's always on the decks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(vm.sortedRooms) { room in
                    NavigationLink(value: room) {
                        RoomCardView(room: room, vm: vm)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

struct RoomCardView: View {
    let room: Room
    let vm: LobbyViewModel

    private var theme: Theme { ThemeCatalog.theme(for: room.genre) }

    var body: some View {
        let live = vm.isLive(room)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(theme.accent.opacity(0.18))
                Text(RoomConfig.genreEmoji(room.genre)).font(.system(size: 30))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name).font(.headline)
                nowPlayingLine
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(live ? Color.green : Color.gray.opacity(0.6)).frame(width: 7, height: 7)
                    Text("\(vm.listeners(room)) listening")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(live ? .primary : .secondary)
                }
                if room.lineupSize > 0 {
                    Text("\(room.lineupSize) in line")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(live ? theme.accent.opacity(0.45) : .clear, lineWidth: 1))
    }

    @ViewBuilder
    private var nowPlayingLine: some View {
        if room.phase == .playing, let track = room.currentTrack {
            Text("♪ \(track.trackName)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(vm.djName(room).map { "DJ \($0)" } ?? "Auto-DJ")
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        } else if room.phase == .picking {
            Text("\(vm.djName(room) ?? "DJ") is picking…")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else {
            Text("quiet right now")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
