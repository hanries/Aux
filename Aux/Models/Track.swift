//
//  Track.swift
//  Aux
//
//  A playable 30s clip. Stored verbatim as the `current_track` / `cued_track`
//  jsonb in Postgres, and produced by iTunes search. Keys are camelCase to match
//  both the iTunes API and the seeded `default_tracks` rows.
//

import Foundation

struct Track: Codable, Hashable, Identifiable {
    let trackId: String
    let trackName: String
    let artistName: String
    let artworkUrl100: String?
    let previewUrl: String

    var id: String { trackId }

    /// Upscale the 100×100 art to something crisp for the now-playing view.
    var artworkURLLarge: URL? {
        guard let art = artworkUrl100 else { return nil }
        return URL(string: art.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
    }

    var artworkURLSmall: URL? {
        guard let art = artworkUrl100 else { return nil }
        return URL(string: art)
    }

    var previewURL: URL? { URL(string: previewUrl) }
}
