//
//  ThemedBackground.swift
//  Aux
//
//  The room backdrop: a themed gradient + a modest ambient-motion layer. Replaces
//  NightBackground inside the room only (app chrome stays neutral).
//

import SwiftUI

struct ThemedBackground: View {
    let theme: Theme

    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.bgTop, theme.bgBottom],
                startPoint: .top, endPoint: .bottom)

            ambient
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
    }

    @ViewBuilder
    private var ambient: some View {
        switch theme.ambient {
        case .warmDrift:
            glow(theme.djAccent, 0.22, size: 320)
                .offset(x: drift ? -90 : 90, y: drift ? -140 : -90)
                .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: drift)
            glow(theme.accent, 0.16, size: 280)
                .offset(x: drift ? 110 : -70, y: drift ? 220 : 280)
                .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: drift)

        case .neonPulse:
            glow(theme.djAccent, drift ? 0.42 : 0.22, size: 300)
                .offset(x: -100, y: -120)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: drift)
            glow(theme.accent, drift ? 0.38 : 0.18, size: 320)
                .offset(x: 120, y: 240)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: drift)

        case .retro:
            glow(theme.accent, 0.18, size: 300)
                .offset(x: drift ? 70 : -60, y: drift ? -120 : -80)
                .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: drift)
            glow(theme.djAccent, 0.14, size: 260)
                .offset(x: drift ? -90 : 60, y: 260)
                .animation(.easeInOut(duration: 20).repeatForever(autoreverses: true), value: drift)
        }
    }

    private func glow(_ color: Color, _ opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 90)
    }
}
