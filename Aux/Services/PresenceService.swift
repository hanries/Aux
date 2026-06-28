//
//  PresenceService.swift
//  Aux
//
//  Per-user "which room am I in right now", denormalized onto users so the
//  Following list can show who's live. Pass nil to clear on leave/background.
//

import Foundation
import Supabase
import PostgREST

struct PresenceService {
    func set(roomID: String?) async throws {
        try await supabase.rpc("set_presence", params: PresenceParam(p_room_id: roomID)).execute()
    }
}

struct PresenceParam: Encodable {
    let p_room_id: String?

    enum CodingKeys: String, CodingKey { case p_room_id }

    // Always send the key, as JSON null when clearing (PostgREST omits nil
    // optionals otherwise → no matching overload).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let roomID = p_room_id {
            try c.encode(roomID, forKey: .p_room_id)
        } else {
            try c.encodeNil(forKey: .p_room_id)
        }
    }
}
