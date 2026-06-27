//
//  RootView.swift
//  Aux
//
//  Routes between loading / unconfigured / onboarding / room.
//

import SwiftUI

struct RootView: View {
    @State private var session = AppSession()

    var body: some View {
        ZStack {
            NightBackground()
            content
        }
        .preferredColorScheme(.dark)
        .task {
            if case .loading = session.state { await session.bootstrap() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .loading:
            LoadingView(label: "Tuning in…")

        case .unconfigured:
            UnconfiguredView()

        case .onboarding(let userID):
            OnboardingView(userID: userID, auth: session.auth) { profile in
                session.completeOnboarding(profile)
            }

        case .ready(let profile):
            NavigationStack {
                LobbyView(profile: profile)
                    .navigationDestination(for: Room.self) { room in
                        RoomView(profile: profile, room: room)
                    }
            }
            .id(profile.id)

        case .failed(let message):
            ErrorView(message: message) { session.retry() }
        }
    }
}

/// Shown until real Supabase credentials are pasted into Secrets.swift.
private struct UnconfiguredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🎧").font(.system(size: 56))
            Text("Almost there")
                .font(.title2.bold())
            Text("Add your Supabase Project URL and anon key to\nAux/Config/Secrets.swift, then run the schema SQL.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
