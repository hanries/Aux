//
//  CategoriesViewModel.swift
//  Aux
//
//  Home brain: categories + their live room instances. One LobbyChannel
//  subscription keeps every room fresh; we group by category for the browse list
//  and route joins through `join_category`.
//

import Foundation
import Observation

@MainActor
@Observable
final class CategoriesViewModel {

    enum LoadState: Equatable { case loading, ready, failed(String) }

    let profile: UserProfile
    let serverClock = ServerClock.shared

    private(set) var loadState: LoadState = .loading
    private(set) var categories: [Category] = []
    private(set) var rooms: [Room] = []
    private(set) var profileCache: [String: UserProfile] = [:]
    var tick = 0

    private let channel = LobbyChannel()
    private let roomService = RoomService()
    private let categoryService = CategoryService()
    private let auth = AuthService()
    private var roomsByID: [String: Room] = [:]
    private var eventTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var started = false

    init(profile: UserProfile) { self.profile = profile }

    // MARK: - Derived

    func rooms(in categoryID: String) -> [Room] {
        _ = tick
        let now = serverClock.now
        return rooms.filter { $0.categoryId == categoryID }.sorted { a, b in
            let la = a.isLive(now: now), lb = b.isLive(now: now)
            if la != lb { return la }
            if a.listeners != b.listeners { return a.listeners > b.listeners }
            return (a.instanceNo ?? 1) < (b.instanceNo ?? 1)
        }
    }

    func isLive(_ room: Room) -> Bool { _ = tick; return room.isLive(now: serverClock.now) }
    func listeners(_ room: Room) -> Int { isLive(room) ? room.listeners : 0 }

    func liveListeners(in categoryID: String) -> Int {
        rooms(in: categoryID).reduce(0) { $0 + listeners($1) }
    }
    func liveRoomCount(in categoryID: String) -> Int {
        rooms(in: categoryID).filter { isLive($0) }.count
    }

    func djName(_ room: Room) -> String? {
        guard let dj = room.currentDjId else { return nil }
        if dj == profile.id { return profile.handle }
        return profileCache[dj]?.handle
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        serverClock.start()
        await serverClock.calibrate()

        do {
            categories = try await categoryService.fetchCategories()
            let all = try await roomService.fetchAllRooms()
            for room in all { roomsByID[room.id] = room }
            rooms = Array(roomsByID.values)
            loadState = .ready
        } catch {
            loadState = .failed("Couldn't load rooms. Pull to retry.")
            return
        }
        await ensureDJProfiles()

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await room in self.channel.events {
                self.roomsByID[room.id] = room
                self.rooms = Array(self.roomsByID.values)
                await self.ensureDJProfiles()
            }
        }
        startTicker()
        await channel.start()
    }

    func stop() async {
        eventTask?.cancel(); tickTask?.cancel()
        await channel.stop()
        started = false
    }

    /// Route into the best instance of a category; returns the room id to open.
    func join(_ category: Category) async -> String? {
        try? await categoryService.joinCategory(category.id)
    }

    private func ensureDJProfiles() async {
        let ids = rooms.compactMap { $0.currentDjId }
        let missing = Set(ids).subtracting(profileCache.keys).subtracting([profile.id])
            .filter { !$0.isEmpty }
        guard !missing.isEmpty else { return }
        if let fetched = try? await auth.fetchProfiles(ids: Array(missing)) {
            for profile in fetched { profileCache[profile.id] = profile }
        }
    }

    private func startTicker() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick &+= 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
