//
//  ITunesSearchService.swift
//  Aux
//
//  Free iTunes Search API (no key). Returns 30s preview clips. We drop results
//  without a `previewUrl` (not all songs have one) and normalize the numeric
//  `trackId` to a String to match how we store tracks in Postgres.
//

import Foundation

struct ITunesSearchService {

    enum SearchError: LocalizedError {
        case badResponse
        var errorDescription: String? { "Couldn't reach the music library. Try again." }
    }

    func search(_ query: String, limit: Int = 25) async throws -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else { throw SearchError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SearchError.badResponse
        }

        let decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
        return decoded.results.compactMap { $0.asTrack }
    }
}

// MARK: - Raw API DTOs

private struct ITunesResponse: Decodable {
    let results: [ITunesTrack]
}

private struct ITunesTrack: Decodable {
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let artworkUrl100: String?
    let previewUrl: String?

    var asTrack: Track? {
        guard let trackId, let trackName, let artistName, let previewUrl else { return nil }
        return Track(
            trackId: String(trackId),
            trackName: trackName,
            artistName: artistName,
            artworkUrl100: artworkUrl100,
            previewUrl: previewUrl
        )
    }
}
