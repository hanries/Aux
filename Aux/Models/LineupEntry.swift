//
//  LineupEntry.swift
//  Aux
//
//  One DJ in the rotation. Display info (handle/avatar) is resolved separately
//  from presence, since realtime row changes only carry the raw lineup columns.
//

import Foundation

struct LineupEntry: Codable, Identifiable {
    let roomId: String
    let userId: String
    let position: Double
    let cuedTrack: Track?

    var id: String { userId }
    var hasCued: Bool { cuedTrack != nil }

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case userId = "user_id"
        case position
        case cuedTrack = "cued_track"
    }
}
