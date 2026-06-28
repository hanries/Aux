//
//  RoomView.swift
//  Aux
//
//  The stage. Thin shell that composes the now-playing card, the round stage
//  (vote / reveal / picking), the DJ booth and the audience, with chat + search
//  as sheets.
//

import SwiftUI

struct RoomView: View {
    let profile: UserProfile
    let room: Room

    @State private var vm: RoomViewModel
    @State private var showSearch = false
    @State private var showChat = false
    @State private var showTwins = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ConnectionsModel.self) private var connections

    init(profile: UserProfile, room: Room) {
        self.profile = profile
        self.room = room
        _vm = State(initialValue: RoomViewModel(
            profile: profile, roomID: room.id, initialRoom: room))
    }

    var body: some View {
        ZStack {
            NightBackground()
            switch vm.loadState {
            case .loading:
                LoadingView(label: "Joining \(room.name)…")
            case .failed(let message):
                ErrorView(message: message) { Task { await vm.start() } }
            case .ready:
                stage
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await vm.start(); vm.applyBlocked(connections.blockedIDs) }
        .onDisappear { Task { await vm.stop() } }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: Task { await vm.enterBackground() }
            case .active: Task { await vm.enterForeground() }
            default: break
            }
        }
        .onChange(of: connections.blockedIDs) { _, ids in vm.applyBlocked(ids) }
        .sheet(isPresented: $showSearch) {
            SearchView(vm: vm)
        }
        .sheet(isPresented: $showChat) {
            ChatView(vm: vm)
        }
        .sheet(isPresented: $showTwins) {
            TasteTwinsView(vm: vm).environment(connections)
        }
    }

    private var stage: some View {
        ScrollView {
            VStack(spacing: 20) {
                NowPlayingView(vm: vm)
                roundStage
                DJBoothView(vm: vm) { showSearch = true }
                AudienceView(vm: vm)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var roundStage: some View {
        switch vm.roundStage {
        case .voting:
            VotePanelView(vm: vm)
        case .reveal:
            RevealView(vm: vm)
        case .picking:
            PickingBanner(vm: vm) { showSearch = true }
        case .idle:
            Text("Warming up the room…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Label("\(vm.audience.count)", systemImage: "person.2.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showTwins = true
                Task { await vm.refreshTasteTwins(force: true) }
            } label: {
                Image(systemName: "sparkles")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showChat = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
            }
        }
    }
}

/// Shown while the on-deck DJ is choosing a track.
struct PickingBanner: View {
    let vm: RoomViewModel
    let onPick: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if vm.amOnDeck {
                Text("You're up! 🎧")
                    .font(.headline)
                Text("Cue a track before the timer runs out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Pick a track", action: onPick)
                    .buttonStyle(.borderedProminent)
            } else {
                Text("\(vm.onDeckName) is picking…")
                    .font(.headline)
            }
            if let left = vm.pickingSecondsLeft {
                Text("\(left)s")
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
