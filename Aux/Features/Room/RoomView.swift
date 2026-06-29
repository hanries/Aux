//
//  RoomView.swift
//  Aux
//
//  The people-first room: the crowd is the hero, the DJ is on stage, and the
//  reaction bar is the primary action. Chat / search / taste-twins are sheets.
//

import SwiftUI

struct RoomView: View {
    let profile: UserProfile
    let room: Room

    @State private var vm: RoomViewModel
    @State private var showSearch = false
    @State private var showChat = false
    @State private var showTwins = false
    @State private var profileTarget: UserRef?
    @State private var dmTarget: DMTarget?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ConnectionsModel.self) private var connections
    private let dmService = DMService()

    init(profile: UserProfile, room: Room) {
        self.profile = profile
        self.room = room
        _vm = State(initialValue: RoomViewModel(
            profile: profile, roomID: room.id, initialRoom: room))
    }

    private var theme: Theme { ThemeCatalog.theme(for: room.genre) }

    var body: some View {
        ZStack {
            ThemedBackground(theme: theme)
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
        .environment(\.roomTheme, theme)
        .tint(theme.accent)
        .safeAreaInset(edge: .bottom) {
            if case .ready = vm.loadState { ReactionBarView(vm: vm) }
        }
        .overlay(alignment: .top) { banners }
        .overlay(alignment: .bottomTrailing) {
            ReactionOverlay(vm: vm).padding(.trailing, 12).padding(.bottom, 80)
        }
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
        .sheet(isPresented: $showSearch) { SearchView(vm: vm) }
        .sheet(isPresented: $showChat) { ChatView(vm: vm) }
        .sheet(isPresented: $showTwins) { TasteTwinsView(vm: vm).environment(connections) }
        .sheet(item: $profileTarget) { ref in
            ProfileSheet(userID: ref.id).environment(connections)
        }
        .sheet(item: $dmTarget) { target in
            NavigationStack {
                DMThreadView(profile: profile, dmID: target.dmID, otherID: target.otherID,
                             otherHandle: target.otherHandle, otherAvatar: target.otherAvatar)
            }
            .preferredColorScheme(.dark)
        }
    }

    private var stage: some View {
        ScrollView {
            VStack(spacing: 18) {
                DJStageView(vm: vm)
                if vm.roundStage == .picking {
                    PickingBanner(vm: vm) { showSearch = true }
                }
                CrowdView(vm: vm,
                          onWave: { id in Task { await vm.wave(at: id) } },
                          onProfile: { id in profileTarget = UserRef(id: id) })
                DJBoothView(vm: vm) { showSearch = true }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 8) {
            if let toast = vm.waveToast {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            if let spark = vm.spark {
                TasteSparkView(
                    spark: spark,
                    onWave: { Task { await vm.wave(at: spark.userID); vm.dismissSpark() } },
                    onMessage: { Task { await openDM(with: spark) } },
                    onDismiss: { vm.dismissSpark() })
            }
        }
        .padding(.top, 4)
        .animation(.spring(duration: 0.3), value: vm.spark)
        .animation(.easeInOut, value: vm.waveToast)
    }

    private func openDM(with spark: RoomViewModel.Spark) async {
        guard let dmID = try? await dmService.openThread(with: spark.userID) else { return }
        vm.dismissSpark()
        dmTarget = DMTarget(dmID: dmID, otherID: spark.userID,
                            otherHandle: spark.handle, otherAvatar: spark.avatar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showTwins = true
                Task { await vm.refreshTasteTwins(force: true) }
            } label: { Image(systemName: "sparkles") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showChat = true } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
            }
        }
    }
}

/// Shown while the on-deck DJ is lining up their next clip.
struct PickingBanner: View {
    let vm: RoomViewModel
    let onPick: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if vm.amOnDeck {
                Text("You're on the decks 🎧").font(.headline)
                Text("Add a track to your set before the timer runs out.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Add a track", action: onPick).buttonStyle(.borderedProminent)
            } else {
                Text("\(vm.onDeckName) is lining one up…").font(.headline)
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
