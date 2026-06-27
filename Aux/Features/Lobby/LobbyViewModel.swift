//
//  LobbyViewModel.swift
//  Aux
//
//  The home screen brain. One realtime subscription to `rooms` (via LobbyChannel)
//  drives a live, active-first room list. Counts come from the denormalized
//  columns the room leaders keep fresh; a 1s ticker re-evaluates heartbeat
//  freshness so rooms that go quiet fade to idle on their own.
//

import Foundation
import Observation

@MainActor
@Observable
final class LobbyViewModel {

    enum LoadState: Equatable {
        case loading, ready, failed(String)
    }

    let profile: UserProfile
    let serverClock = ServerClock.shared

    private(set) var loadState: LoadState = .loading
    private(set) var rooms: [Room] = []
    private(set) var profileCache: [String: UserProfile] = [:]
    var tick = 0

    private let channel = LobbyChannel()
    private let roomService = RoomService()
    private let auth = AuthService()
    private var roomsByID: [String: Room] = [:]
    private var eventTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var started = false

    init(profile: UserProfile) {
        self.profile = profile
    }

    // MARK: - Derived

    /// Active rooms first, then by listeners, lineup, name.
    var sortedRooms: [Room] {
        _ = tick
        let now = serverClock.now
        return rooms.sorted { a, b in
            let la = a.isLive(now: now), lb = b.isLive(now: now)
            if la != lb { return la }
            if a.listeners != b.listeners { return a.listeners > b.listeners }
            if a.lineupSize != b.lineupSize { return a.lineupSize > b.lineupSize }
            return a.name < b.name
        }
    }

    func isLive(_ room: Room) -> Bool {
        _ = tick
        return room.isLive(now: serverClock.now)
    }

    func listeners(_ room: Room) -> Int { isLive(room) ? room.listeners : 0 }

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
        eventTask?.cancel()
        tickTask?.cancel()
        await channel.stop()
        started = false
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
