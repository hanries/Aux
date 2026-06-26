//
//  RoomService.swift
//  Aux
//
//  One-shot reads of the room row. Live updates come through RoomChannel.
//

import Foundation
import Supabase
import PostgREST

struct RoomService {

    enum RoomError: LocalizedError {
        case notFound
        var errorDescription: String? { "Room not found. Did you run the seed SQL?" }
    }

    func fetchRoom(id: String) async throws -> Room {
        let rows: [Room] = try await supabase
            .from("rooms")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        guard let room = rows.first else { throw RoomError.notFound }
        return room
    }
}
