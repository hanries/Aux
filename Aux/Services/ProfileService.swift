//
//  ProfileService.swift
//  Aux
//
//  Assembles the lightweight profile card: identity + DJ hot-rating + a few
//  recent Hot picks. Built from existing votes queries — no new RPC.
//

import Foundation
import Supabase
import PostgREST

struct ProfileService {
    private let auth = AuthService()

    func card(userID: String) async throws -> ProfileCard {
        let profile = (try? await auth.fetchProfile(id: userID))
            ?? UserProfile(id: userID, handle: "someone", avatar: "🎧")

        async let djVotesReq: [Vote] = supabase
            .from("votes").select().eq("dj_id", value: userID).execute().value
        async let hotVotesReq: [Vote] = supabase
            .from("votes").select()
            .eq("voter_id", value: userID).eq("vote", value: "hot")
            .order("created_at", ascending: false).limit(20).execute().value

        let djVotes = (try? await djVotesReq) ?? []
        let hotVotes = (try? await hotVotesReq) ?? []

        var seen = Set<String>()
        var picks: [Track] = []
        for vote in hotVotes {
            guard let track = vote.track, !seen.contains(track.trackId) else { continue }
            seen.insert(track.trackId)
            picks.append(track)
        }

        return ProfileCard(
            profile: profile,
            djHotVotes: djVotes.filter { $0.vote == .hot }.count,
            djTotalVotes: djVotes.count,
            recentHotPicks: Array(picks.prefix(6)))
    }
}
