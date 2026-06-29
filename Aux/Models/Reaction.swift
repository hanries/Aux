//
//  Reaction.swift
//  Aux
//
//  The primary audience action — a live, attributed emote. `love` doubles as the
//  taste-twin / save signal; `wave` is directed (carries target_user_id).
//

import Foundation

enum ReactionType: String, Codable, CaseIterable, Identifiable {
    case fire, hands, laugh, wave, love

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fire:  return "🔥"
        case .hands: return "🙌"
        case .laugh: return "😂"
        case .wave:  return "👋"
        case .love:  return "💜"
        }
    }

    /// The palette shown in the reaction bar (wave is sent by tapping a person).
    static var palette: [ReactionType] { [.fire, .hands, .laugh, .love] }
}

struct Reaction: Codable, Identifiable {
    let id: String
    let roomId: String
    let roundId: String?
    let trackId: String?
    let djId: String?
    let userId: String
    let type: ReactionType
    let targetUserId: String?
    let track: Track?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case roundId = "round_id"
        case trackId = "track_id"
        case djId = "dj_id"
        case userId = "user_id"
        case type
        case targetUserId = "target_user_id"
        case track
    }
}

/// Insert payload (server fills `id` + `created_at`).
struct ReactionInsert: Encodable {
    let room_id: String
    let round_id: String?
    let track_id: String?
    let dj_id: String?
    let user_id: String
    let type: String
    let target_user_id: String?
    let track: Track?
}
