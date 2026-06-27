//
//  AuthService.swift
//  Aux
//
//  Lightweight anonymous auth. supabase-swift persists the session, so a user
//  keeps the same identity (and handle/avatar) across launches.
//
//  NOTE: all user ids are lowercased to match Postgres' uuid text form, so
//  string comparisons against `current_dj_id`, `voter_id`, etc. line up.
//

import Foundation
import Supabase
import Auth
import PostgREST

struct AuthService {

    /// Returns the current user id, signing in anonymously the first time.
    func ensureSignedIn() async throws -> String {
        if let user = supabase.auth.currentUser {
            return user.id.uuidString.lowercased()
        }
        let session = try await supabase.auth.signInAnonymously()
        return session.user.id.uuidString.lowercased()
    }

    var currentUserID: String? {
        supabase.auth.currentUser?.id.uuidString.lowercased()
    }

    func fetchProfile(id: String) async throws -> UserProfile? {
        let rows: [UserProfile] = try await supabase
            .from("users")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func upsertProfile(_ profile: UserProfileUpsert) async throws {
        try await supabase.from("users").upsert(profile).execute()
    }

    /// Durable identity lookup for a set of user ids (booth, voters, chat senders),
    /// independent of who is currently present.
    func fetchProfiles(ids: [String]) async throws -> [UserProfile] {
        guard !ids.isEmpty else { return [] }
        return try await supabase
            .from("users")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }
}
