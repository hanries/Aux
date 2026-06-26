//
//  SharedViews.swift
//  Aux
//
//  Small reusable building blocks.
//

import SwiftUI

/// Emoji avatar in a soft circle, with an optional accent ring (on-deck/host).
struct AvatarView: View {
    let emoji: String
    var size: CGFloat = 44
    var ring: Color? = nil

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().strokeBorder(ring ?? .clear, lineWidth: 2.5))
    }
}

struct LoadingView: View {
    var label = "Loading…"
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// App-wide dark "2am" backdrop.
struct NightBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.07, blue: 0.16),
                     Color(red: 0.03, green: 0.03, blue: 0.07)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
