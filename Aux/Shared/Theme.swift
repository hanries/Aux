//
//  Theme.swift
//  Aux
//
//  The theme-token system: one room engine, many skins. A Theme is config — only
//  the *look* (palette, type, ambient motion) varies by category; the interaction
//  model never does. Resolved from the room's `genre` for now (Phase 3 keys it off
//  categories.theme_key via the same catalog).
//

import SwiftUI

enum AmbientStyle {
    case warmDrift   // slow, dim, cozy
    case neonPulse   // fast, bright, loud
    case retro       // gentle, warm
}

struct Theme: Equatable {
    let key: String
    let name: String
    // palette
    let bgTop: Color
    let bgBottom: Color
    let accent: Color        // primary controls / rings
    let djAccent: Color      // the DJ on stage (ring, progress, warmth)
    let loveAccent: Color    // the love reaction + taste spark
    // type
    let fontDesign: Font.Design
    // motion
    let ambient: AmbientStyle
}

enum ThemeCatalog {
    /// Warm / Lo-Fi — dim, cozy.
    static let warm = Theme(
        key: "warm", name: "Lo-Fi",
        bgTop: Color(red: 0.10, green: 0.08, blue: 0.17),
        bgBottom: Color(red: 0.04, green: 0.03, blue: 0.08),
        accent: Color(red: 0.85, green: 0.62, blue: 0.45),     // warm amber
        djAccent: Color(red: 0.78, green: 0.55, blue: 0.90),   // soft purple
        loveAccent: Color(red: 0.95, green: 0.55, blue: 0.70),
        fontDesign: .rounded,
        ambient: .warmDrift)

    /// Neon / Hyperpop — loud, bright.
    static let neon = Theme(
        key: "neon", name: "Hyperpop",
        bgTop: Color(red: 0.10, green: 0.02, blue: 0.18),
        bgBottom: Color(red: 0.02, green: 0.02, blue: 0.06),
        accent: Color(red: 0.0, green: 0.92, blue: 0.96),      // cyan
        djAccent: Color(red: 1.0, green: 0.20, blue: 0.66),    // hot pink
        loveAccent: Color(red: 1.0, green: 0.30, blue: 0.80),
        fontDesign: .rounded,
        ambient: .neonPulse)

    /// Retro / 2000s — warm, nostalgic.
    static let retro = Theme(
        key: "retro", name: "2000s",
        bgTop: Color(red: 0.06, green: 0.12, blue: 0.16),
        bgBottom: Color(red: 0.03, green: 0.05, blue: 0.07),
        accent: Color(red: 0.95, green: 0.70, blue: 0.30),     // retro orange
        djAccent: Color(red: 0.30, green: 0.80, blue: 0.78),   // teal
        loveAccent: Color(red: 0.96, green: 0.50, blue: 0.45),
        fontDesign: .default,
        ambient: .retro)

    static func theme(for genre: String) -> Theme {
        switch genre {
        case "hyperpop", "dnb":            return neon
        case "throwback":                  return retro
        case "lofi", "bedroom", "sadindie": return warm
        default:                           return warm
        }
    }
}

// MARK: - Environment

private struct RoomThemeKey: EnvironmentKey {
    static let defaultValue: Theme = ThemeCatalog.warm
}

extension EnvironmentValues {
    var roomTheme: Theme {
        get { self[RoomThemeKey.self] }
        set { self[RoomThemeKey.self] = newValue }
    }
}
