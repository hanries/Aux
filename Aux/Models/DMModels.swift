//
//  DMModels.swift
//  Aux
//

import Foundation

/// One 1:1 thread row (from the `my_dms` RPC).
struct DMThread: Codable, Identifiable, Hashable {
    let dmId: String
    let otherId: String
    let otherHandle: String
    let otherAvatar: String
    let lastText: String?
    let lastMs: Double?
    let lastSenderId: String?
    let unread: Bool

    var id: String { dmId }

    enum CodingKeys: String, CodingKey {
        case dmId = "dm_id"
        case otherId = "other_id"
        case otherHandle = "other_handle"
        case otherAvatar = "other_avatar"
        case lastText = "last_text"
        case lastMs = "last_ms"
        case lastSenderId = "last_sender_id"
        case unread
    }
}

struct DMMessage: Codable, Identifiable {
    let id: String
    let dmId: String
    let senderId: String
    let text: String
    let createdMs: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case dmId = "dm_id"
        case senderId = "sender_id"
        case text
        case createdMs = "created_ms"
    }
}
