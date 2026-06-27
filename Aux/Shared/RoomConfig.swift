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

    /// How often a room's leader writes its audience heartbeat.
    static let heartbeatInterval: TimeInterval = 8

    /// The lobby treats a room whose heartbeat is older than this as idle (0
    /// listening) — so empty rooms self-heal without anyone writing a final 0.
    static let lobbyStaleAfter: TimeInterval = 18

    /// A little visual identity per genre for the lobby cards.
    static func genreEmoji(_ genre: String) -> String {
        switch genre {
        case "lofi":      return "🌙"
        case "hyperpop":  return "⚡️"
        case "throwback": return "📼"
        case "bedroom":   return "🛏️"
        case "dnb":       return "🥁"
        case "sadindie":  return "🥀"
        default:          return "🎧"
        }
    }
}
