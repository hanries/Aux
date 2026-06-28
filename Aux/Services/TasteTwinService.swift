//
//  TasteTwinService.swift
//  Aux
//
//  Vote-overlap matches for the current user in a room. All scoring is in the
//  `taste_twins` Postgres RPC; the client just renders the result.
//

import Foundation
import Supabase
import PostgREST

struct TasteTwinService {
    func fetch(
        roomID: String,
        minShared: Int = RoomConfig.tasteTwinMinShared,
        recencyMinutes: Int = RoomConfig.tasteTwinRecencyMinutes
    ) async throws -> [TasteTwin] {
        try await supabase
            .rpc("taste_twins", params: TasteTwinParams(
                p_room_id: roomID, p_min_shared: minShared, p_recency_minutes: recencyMinutes))
            .execute()
            .value
    }
}

struct TasteTwinParams: Encodable {
    let p_room_id: String
    let p_min_shared: Int
    let p_recency_minutes: Int
}
