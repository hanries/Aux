//
//  ConnectionsModel.swift
//  Aux
//
//  App-scoped connection state: who I follow / who follows me, my DM threads +
//  unread, blocked set, and the new-follower badge. Owns the realtime subs (dms +
//  follows, RLS-scoped to me) and a light periodic refresh so "live" status and
//  the inbox stay current. Shared via @Environment so cards everywhere can read
//  follow/block state and act.
//

import Foundation
import Observation
import Supabase
import Realtime

@MainActor
@Observable
final class ConnectionsModel {

    let profile: UserProfile

    private(set) var following: [FollowUser] = []
    private(set) var followers: [Follower] = []
    private(set) var threads: [DMThread] = []
    private(set) var blockedIDs: Set<String> = []
    private(set) var newFollowerBadge = 0

    var unreadCount: Int { threads.filter(\.unread).count }

    private let followService = FollowService()
    private let blockService = BlockService()
    private let dmService = DMService()

    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private var pollTask: Task<Void, Never>?
    private var knownFollowerIDs: Set<String> = []
    private var started = false

    init(profile: UserProfile) {
        self.profile = profile
    }

    // MARK: - Lookups used by cards everywhere

    func isFollowing(_ id: String) -> Bool { following.contains { $0.userId == id } }
    func isBlocked(_ id: String) -> Bool { blockedIDs.contains(id) }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        await refreshAll()
        knownFollowerIDs = Set(followers.map(\.userId))
        await subscribe()
        startPolling()
    }

    func stop() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        pollTask?.cancel()
        if let channel { await channel.unsubscribe() }
        channel = nil
        started = false
    }

    func refreshAll() async {
        blockedIDs = (try? await blockService.blockedIDs()) ?? blockedIDs
        following = (try? await followService.following()) ?? following
        followers = (try? await followService.followers()) ?? followers
        threads = (try? await dmService.threads()) ?? threads
    }

    func refreshFollowing() async {
        following = (try? await followService.following()) ?? following
    }

    func refreshThreads() async {
        threads = (try? await dmService.threads()) ?? threads
    }

    func clearFollowerBadge() {
        newFollowerBadge = 0
        knownFollowerIDs = Set(followers.map(\.userId))
    }

    // MARK: - Actions

    func follow(_ id: String) async {
        try? await followService.follow(id)
        await refreshFollowing()
    }

    func unfollow(_ id: String) async {
        try? await followService.unfollow(id)
        await refreshFollowing()
    }

    func block(_ id: String) async {
        try? await blockService.block(id)
        blockedIDs.insert(id)
        await refreshAll()
    }

    func unblock(_ id: String) async {
        try? await blockService.unblock(id)
        blockedIDs.remove(id)
        await refreshAll()
    }

    // MARK: - Realtime + polling

    private func subscribe() async {
        let channel = supabase.channel("connections:\(profile.id)")
        self.channel = channel

        let dmsStream = channel.postgresChange(AnyAction.self, schema: "public", table: "dms")
        let followStream = channel.postgresChange(
            InsertAction.self, schema: "public", table: "follows")

        await channel.subscribe()

        tasks.append(Task { [weak self] in
            for await _ in dmsStream { await self?.refreshThreads() }
        })
        tasks.append(Task { [weak self] in
            for await change in followStream {
                guard let self,
                      let row = RealtimeDecode.decode(FollowEvent.self, from: change.record),
                      row.followeeId == self.profile.id,
                      !self.knownFollowerIDs.contains(row.followerId)
                else { continue }
                self.knownFollowerIDs.insert(row.followerId)
                self.newFollowerBadge += 1
                self.followers = (try? await self.followService.followers()) ?? self.followers
            }
        })
    }

    /// Keeps "live" status + the inbox fresh without users-table realtime.
    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                await self?.refreshFollowing()
                await self?.refreshThreads()
            }
        }
    }

    private struct FollowEvent: Decodable {
        let followerId: String
        let followeeId: String
        enum CodingKeys: String, CodingKey {
            case followerId = "follower_id"
            case followeeId = "followee_id"
        }
    }
}
