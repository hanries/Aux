//
//  ChatMessage.swift
//  Aux
//

import Foundation

struct ChatMessage: Codable, Identifiable {
    let id: String
    let roomId: String
    let userId: String
    let text: String
    let createdAt: String?   // kept as text; used only for stable ordering

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case userId = "user_id"
        case text
        case createdAt = "created_at"
    }
}

/// Insert payload (server fills `id` + `created_at`).
struct ChatMessageInsert: Encodable {
    let room_id: String
    let user_id: String
    let text: String
}
