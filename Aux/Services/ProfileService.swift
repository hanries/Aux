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

        // Reactions earned as a DJ (love = warmth) and tracks this user loved.
        async let djReactionsReq: [Reaction] = supabase
            .from("reactions").select().eq("dj_id", value: userID).execute().value
        async let lovedReq: [Reaction] = supabase
            .from("reactions").select()
            .eq("user_id", value: userID).eq("type", value: "love")
            .order("created_at", ascending: false).limit(30).execute().value

        let djReactions = (try? await djReactionsReq) ?? []
        let loved = (try? await lovedReq) ?? []

        var seen = Set<String>()
        var picks: [Track] = []
        for reaction in loved {
            guard let track = reaction.track, !seen.contains(track.trackId) else { continue }
            seen.insert(track.trackId)
            picks.append(track)
        }

        return ProfileCard(
            profile: profile,
            djHotVotes: djReactions.filter { $0.type == .love }.count,
            djTotalVotes: djReactions.count,
            recentHotPicks: Array(picks.prefix(6)))
    }
}
