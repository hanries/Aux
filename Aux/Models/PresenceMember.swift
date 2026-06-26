//
//  PresenceMember.swift
//  Aux
//
//  What each client publishes to the room's Realtime presence channel. The
//  `joinedAtMs` (server-time estimate) drives host election: the earliest joiner
//  present is the host that drives `advance_room`.
//

import Foundation

struct PresenceMember: Codable, Identifiable, Hashable {
    let userId: String
    let handle: String
    let avatar: String
    let joinedAtMs: Double

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case handle
        case avatar
        case joinedAtMs = "joined_at_ms"
    }
}
