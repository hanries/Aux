//
//  ConnectionModels.swift
//  Aux
//
//  Milestone 3 — the connection layer. Rows returned by the taste-twin / follow
//  RPCs, plus the assembled profile card.
//

import Foundation

/// One taste-twin match (from the `taste_twins` RPC).
struct TasteTwin: Codable, Identifiable {
    let otherId: String
    let handle: String
    let avatar: String
    let shared: Int
    let agree: Int
    let agreement: Double
    let sharedHot: Int
    let sharedHotTracks: [Track]

    var id: String { otherId }
    var agreementPercent: Int { Int((agreement * 100).rounded()) }
    /// "matched on 8/10"
    var matchText: String { "matched on \(agree)/\(shared)" }

    enum CodingKeys: String, CodingKey {
        case otherId = "other_id"
        case handle, avatar, shared, agree, agreement
        case sharedHot = "shared_hot"
        case sharedHotTracks = "shared_hot_tracks"
    }
}

/// Someone I follow + whether they're live right now (from `my_following`).
struct FollowUser: Codable, Identifiable {
    let userId: String
    let handle: String
    let avatar: String
    let roomId: String?
    let roomName: String?
    let isLive: Bool

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case handle, avatar
        case roomId = "room_id"
        case roomName = "room_name"
        case isLive = "is_live"
    }
}

/// Someone who follows me (from `my_followers`).
struct Follower: Codable, Identifiable {
    let userId: String
    let handle: String
    let avatar: String
    let iFollowBack: Bool

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case handle, avatar
        case iFollowBack = "i_follow_back"
    }
}

/// Assembled client-side for the lightweight profile sheet.
struct ProfileCard {
    let profile: UserProfile
    let djHotVotes: Int
    let djTotalVotes: Int
    let recentHotPicks: [Track]

    var djRatingText: String? {
        guard djTotalVotes > 0 else { return nil }
        return "\(djHotVotes) 💜 as a DJ · \(djTotalVotes) reaction\(djTotalVotes == 1 ? "" : "s")"
    }
}
