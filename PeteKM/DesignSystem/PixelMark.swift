//
//  PixelMark.swift
//  PeteKM
//
//  The only custom asset in the product (DESIGN.md §6, §57). Always rendered
//  pixelated, never re-drawn by hand, never scaled off the 32 px grid.
//

import SwiftUI

struct PixelMark: View {
    /// Sizes are multiples of 32 (§55).
    var size: CGFloat = 64
    var tint: Color = DS.Color.accent

    var body: some View {
        Image("PixelMark")
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .renderingMode(.template)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityLabel("PeteKM")
    }
}

/// `PETEKM` wordmark. Sanctioned only in the About window and onboarding
/// welcome (§57). Silkscreen is not bundled, so this falls back to a tracked,
/// uppercase monospaced setting rather than shipping a wrong-looking face.
struct Wordmark: View {
    var size: CGFloat = 22
    var tint: Color = DS.Color.textPrimary

    var body: some View {
        Text("PETEKM")
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(size * 0.08)
            .foregroundStyle(tint)
            .accessibilityLabel("PeteKM")
    }
}
