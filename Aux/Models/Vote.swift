//
//  Vote.swift
//  Aux
//

import Foundation

enum VoteKind: String, Codable, CaseIterable {
    case hot
    case skip
}

struct Vote: Codable, Identifiable {
    let id: String
    let roomId: String
    let roundId: String
    let trackId: String
    let djId: String?
    let voterId: String
    let vote: VoteKind
    let track: Track?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case roundId = "round_id"
        case trackId = "track_id"
        case djId = "dj_id"
        case voterId = "voter_id"
        case vote
        case track
    }
}

/// Insert/upsert payload (server fills `id` + `created_at`). `track` is
/// denormalized so taste_twins can show "you both loved these" by name.
struct VoteInsert: Encodable {
    let room_id: String
    let round_id: String
    let track_id: String
    let dj_id: String?
    let voter_id: String
    let vote: String
    let track: Track?
}
