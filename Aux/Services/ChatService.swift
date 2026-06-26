//
//  ChatService.swift
//  Aux
//
//  Room chat reads + sends. Live inserts arrive through RoomChannel.
//

import Foundation
import Supabase
import PostgREST

struct ChatService {

    func fetchRecent(roomID: String, limit: Int = 50) async throws -> [ChatMessage] {
        try await supabase
            .from("messages")
            .select()
            .eq("room_id", value: roomID)
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()
            .value
    }

    func send(roomID: String, userID: String, text: String) async throws {
        let payload = ChatMessageInsert(room_id: roomID, user_id: userID, text: text)
        try await supabase.from("messages").insert(payload).execute()
    }
}
