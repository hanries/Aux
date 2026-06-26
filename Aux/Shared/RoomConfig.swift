//
//  RoomConfig.swift
//  Aux
//
//  Milestone-1 constants. The room id is hardcoded to the single seeded room
//  (see supabase/schema.sql).
//

import Foundation

enum RoomConfig {
    /// The one seeded "2am Lo-Fi" room.
    static let roomID = "11111111-1111-1111-1111-111111111111"

    /// Clip length. iTunes previews are ~30s; we treat them as exactly this.
    static let clipDuration: TimeInterval = 30

    /// How long the reveal/intermission lingers after a clip ends before the
    /// host advances the room. Keep in sync with the feel, not the SQL.
    static let revealWindow: TimeInterval = 6

    /// Re-seek the player if it drifts more than this from the computed position.
    static let driftTolerance: TimeInterval = 1.5
}
