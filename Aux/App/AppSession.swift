//
//  AppSession.swift
//  Aux
//
//  Top-level auth/profile gate. Decides whether to show onboarding or the room.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSession {

    enum State: Equatable {
        case loading
        case unconfigured          // Secrets.swift still has placeholders
        case onboarding(userID: String)
        case ready(UserProfile)
        case failed(String)
    }

    private(set) var state: State = .loading
    let auth = AuthService()

    func bootstrap() async {
        guard Secrets.isConfigured else {
            state = .unconfigured
            return
        }
        do {
            let userID = try await auth.ensureSignedIn()
            if let profile = try await auth.fetchProfile(id: userID) {
                state = .ready(profile)
            } else {
                state = .onboarding(userID: userID)
            }
        } catch {
            state = .failed("Couldn't connect to Supabase. Check your URL/key and that anonymous sign-ins are enabled.")
        }
    }

    func completeOnboarding(_ profile: UserProfile) {
        state = .ready(profile)
    }

    func retry() {
        state = .loading
        Task { await bootstrap() }
    }
}
