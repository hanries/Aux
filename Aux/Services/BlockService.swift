//
//  BlockService.swift
//  Aux
//
//  The safety floor for stranger DMs. Blocking removes mutual follows and (server-
//  side) hides the pair from each other's taste twins / DM / follow.
//

import Foundation
import Supabase
import PostgREST

struct BlockService {
    func block(_ other: String) async throws {
        try await supabase.rpc("block_user", params: OtherUserParam(p_other: other)).execute()
    }

    func unblock(_ other: String) async throws {
        try await supabase.rpc("unblock_user", params: OtherUserParam(p_other: other)).execute()
    }

    /// The ids I've blocked — for client-side hiding (audience, etc.).
    func blockedIDs() async throws -> Set<String> {
        let rows: [BlockRow] = try await supabase
            .from("blocks")
            .select("blocked_id")
            .execute()
            .value
        return Set(rows.map(\.blockedId))
    }
}

private struct BlockRow: Decodable {
    let blockedId: String
    enum CodingKeys: String, CodingKey { case blockedId = "blocked_id" }
}
