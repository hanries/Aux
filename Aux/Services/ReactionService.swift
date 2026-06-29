//
//  ReactionService.swift
//  Aux
//
//  The audience's primary action. Reactions are inserted directly (RLS-guarded to
//  auth.uid()); the live attributed stream + warmth/cold + taste-twin overlap all
//  read off the `reactions` table.
//

import Foundation
import Supabase
import PostgREST

struct ReactionService {
    func react(
        roomID: String,
        roundID: String?,
        trackID: String?,
        djID: String?,
        userID: String,
        type: ReactionType,
        targetUserID: String? = nil,
        track: Track? = nil
    ) async throws {
        let payload = ReactionInsert(
            room_id: roomID, round_id: roundID, track_id: trackID, dj_id: djID,
            user_id: userID, type: type.rawValue, target_user_id: targetUserID, track: track)
        try await supabase.from("reactions").insert(payload).execute()
    }

    /// Recent reactions for the room — to seed the live overlay on join.
    func fetchRecent(roomID: String, limit: Int = 40) async throws -> [Reaction] {
        try await supabase
            .from("reactions")
            .select()
            .eq("room_id", value: roomID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }
}
