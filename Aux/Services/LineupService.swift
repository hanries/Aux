//
//  LineupService.swift
//  Aux
//
//  DJ lineup reads + the rotation RPCs. All mutations go through SECURITY DEFINER
//  functions; the client never writes the lineup table directly.
//

import Foundation
import Supabase
import PostgREST

struct LineupService {

    func fetchLineup(roomID: String) async throws -> [LineupEntry] {
        try await supabase
            .from("dj_lineup")
            .select()
            .eq("room_id", value: roomID)
            .order("position", ascending: true)
            .execute()
            .value
    }

    func stepUp(roomID: String) async throws {
        try await supabase.rpc("step_up", params: RoomIDParam(p_room_id: roomID)).execute()
    }

    func stepDown(roomID: String) async throws {
        try await supabase.rpc("step_down", params: RoomIDParam(p_room_id: roomID)).execute()
    }

    /// Append a clip to my set (and start immediately if I'm on deck mid-grace).
    func cueSet(roomID: String, track: Track) async throws {
        try await supabase
            .rpc("cue_set", params: CueTrackParams(p_room_id: roomID, p_track: track))
            .execute()
    }
}

// MARK: - RPC params

struct RoomIDParam: Encodable {
    let p_room_id: String
}

struct CueTrackParams: Encodable {
    let p_room_id: String
    let p_track: Track
}
