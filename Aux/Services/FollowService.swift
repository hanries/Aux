//
//  FollowService.swift
//  Aux
//
//  Follow / unfollow + the following & followers lists (block-checked server-side).
//

import Foundation
import Supabase
import PostgREST

struct FollowService {
    func follow(_ other: String) async throws {
        try await supabase.rpc("follow_user", params: OtherUserParam(p_other: other)).execute()
    }

    func unfollow(_ other: String) async throws {
        try await supabase.rpc("unfollow_user", params: OtherUserParam(p_other: other)).execute()
    }

    func following() async throws -> [FollowUser] {
        try await supabase
            .rpc("my_following", params: StaleParam(p_stale_ms: RoomConfig.presenceStaleMs))
            .execute()
            .value
    }

    func followers() async throws -> [Follower] {
        try await supabase.rpc("my_followers").execute().value
    }

    /// Just the ids I follow — for quick "am I following X" checks.
    func followingIDs() async throws -> Set<String> {
        let rows: [FollowRow] = try await supabase
            .from("follows")
            .select("followee_id")
            .execute()
            .value
        return Set(rows.map(\.followeeId))
    }
}

struct OtherUserParam: Encodable { let p_other: String }
struct StaleParam: Encodable { let p_stale_ms: Int }

private struct FollowRow: Decodable {
    let followeeId: String
    enum CodingKeys: String, CodingKey { case followeeId = "followee_id" }
}
