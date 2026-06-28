//
//  VoteService.swift
//  Aux
//
//  Casting/changing a vote (upsert on round+voter) and reading the tally for a
//  round (powers the reveal + DJ hot-rating).
//

import Foundation
import Supabase
import PostgREST

struct VoteService {

    func castVote(
        roomID: String,
        roundID: String,
        trackID: String,
        djID: String?,
        voterID: String,
        vote: VoteKind,
        track: Track?
    ) async throws {
        let payload = VoteInsert(
            room_id: roomID,
            round_id: roundID,
            track_id: trackID,
            dj_id: djID,
            voter_id: voterID,
            vote: vote.rawValue,
            track: track
        )
        try await supabase
            .from("votes")
            .upsert(payload, onConflict: "round_id,voter_id")
            .execute()
    }

    func fetchVotes(roundID: String) async throws -> [Vote] {
        try await supabase
            .from("votes")
            .select()
            .eq("round_id", value: roundID)
            .execute()
            .value
    }

    /// All votes a DJ has earned in this room — powers the DJ hot-rating.
    func fetchVotesByDJ(roomID: String, djID: String) async throws -> [Vote] {
        try await supabase
            .from("votes")
            .select()
            .eq("room_id", value: roomID)
            .eq("dj_id", value: djID)
            .execute()
            .value
    }
}
