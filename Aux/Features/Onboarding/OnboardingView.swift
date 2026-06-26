//
//  OnboardingView.swift
//  Aux
//
//  Pick a handle + emoji avatar. Anonymous auth already happened in AppSession;
//  here we just persist the profile.
//

import SwiftUI

@MainActor
@Observable
final class OnboardingViewModel {
    var handle = ""
    var avatar = "🎧"
    var isSaving = false
    var errorText: String?

    let avatars = ["🎧", "🌙", "🔥", "🪐", "🐱", "👽", "💿", "🦊", "🛹", "🌈", "🍣", "🎮"]

    var canSave: Bool {
        handle.trimmingCharacters(in: .whitespaces).count >= 2 && !isSaving
    }

    func save(userID: String, auth: AuthService) async -> UserProfile? {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            try await auth.upsertProfile(.init(id: userID, handle: trimmed, avatar: avatar))
            return UserProfile(id: userID, handle: trimmed, avatar: avatar)
        } catch {
            errorText = "Couldn't save your profile. Try again."
            return nil
        }
    }
}

struct OnboardingView: View {
    let userID: String
    let auth: AuthService
    let onDone: (UserProfile) -> Void

    @State private var model = OnboardingViewModel()
    @FocusState private var handleFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                AvatarView(emoji: model.avatar, size: 96)
                Text("Pick your vibe")
                    .font(.title.bold())
                Text("This is how the room sees you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("handle", text: $model.handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .focused($handleFocused)
                .submitLabel(.done)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.avatars, id: \.self) { emoji in
                    Button {
                        model.avatar = emoji
                    } label: {
                        AvatarView(
                            emoji: emoji, size: 48,
                            ring: model.avatar == emoji ? .accentColor : nil)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = model.errorText {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }

            Button {
                Task {
                    if let profile = await model.save(userID: userID, auth: auth) {
                        onDone(profile)
                    }
                }
            } label: {
                Group {
                    if model.isSaving { ProgressView() } else { Text("Enter the room") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canSave)

            Spacer()
        }
        .padding(28)
        .onAppear { handleFocused = true }
    }
}
