//
//  DS.swift
//  PeteKM
//
//  Design-system tokens mirrored from DESIGN.md §47–§52.
//  Prefer native controls first (§58); reach for these only for metrics and
//  the few surfaces AppKit does not style for us.
//

import SwiftUI
import AppKit

enum DS {

    // MARK: - Color (§47)

    enum Color {
        // Primitives
        static let blue050 = hex(0xEDF3FF)
        static let blue100 = hex(0xD6E3FF)
        static let blue500 = hex(0x0A5CFF)
        static let blue600 = hex(0x0047D6)
        static let blue700 = hex(0x0038A8)
        static let grey150 = hex(0xE3E3E3)
        static let grey300 = hex(0xB8B8B8)
        static let grey400 = hex(0x8E8E8E)
        static let grey500 = hex(0x6B6B6B)

        // Semantic (light/dark pairs per §47 dark overrides)
        static let accent = dynamic(light: 0x0A5CFF, dark: 0x2E72FF)
        static let accentTint = dynamic(light: 0xEDF3FF, dark: 0x12203D)
        static let textPrimary = dynamic(light: 0x000000, dark: 0xFFFFFF)
        static let textSecondary = dynamic(light: 0x6B6B6B, dark: 0xB8B8B8)
        static let textTertiary = dynamic(light: 0x8E8E8E, dark: 0x8E8E8E)
        static let surfaceWindow = dynamic(light: 0xFFFFFF, dark: 0x141414)
        static let surfaceCard = dynamic(light: 0xFFFFFF, dark: 0x1A1A1A)
        static let surfaceSunken = dynamic(light: 0xFAFAFA, dark: 0x101010)
        static let surfaceHover = dynamic(light: 0xEDEDED, dark: 0x252525)
        static let borderHairline = dynamic(light: 0xE3E3E3, dark: 0x2E2E2E)
        static let borderField = dynamic(light: 0xD6D6D6, dark: 0x3A3A3A)
        static let error = dynamic(light: 0xD8342B, dark: 0xE8574E)
        static let warning = dynamic(light: 0xB07500, dark: 0xD79A1F)
        static let success = dynamic(light: 0x1C7A3E, dark: 0x3FA463)

        private static func hex(_ value: Int) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(hex: value))
        }

        private static func dynamic(light: Int, dark: Int) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Type (§49)

    enum Text {
        static let display = Font.system(size: 28, weight: .semibold)
        static let title1 = Font.system(size: 22, weight: .semibold)
        static let title2 = Font.system(size: 17, weight: .semibold)
        static let title3 = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let uiLabel = Font.system(size: 13, weight: .medium)
        static let callout = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 11, weight: .regular)
        static let micro = Font.system(size: 10, weight: .medium)
        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing (§50)

    enum Space {
        static let s1: CGFloat = 2
        static let s2: CGFloat = 4
        static let s3: CGFloat = 6
        static let s4: CGFloat = 8
        static let s5: CGFloat = 12
        static let s6: CGFloat = 16
        static let s7: CGFloat = 20
        static let s8: CGFloat = 24
        static let s9: CGFloat = 32
        static let s10: CGFloat = 40
        static let s11: CGFloat = 56
        static let s12: CGFloat = 72

        static let windowGutter: CGFloat = 16
        static let rowGutter: CGFloat = 10
    }

    enum Radius {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 5
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let window: CGFloat = 10
    }

    // MARK: - Motion (§52)

    enum Duration {
        static let instant: Double = 0.08
        static let fast: Double = 0.12
        static let base: Double = 0.18
        static let slow: Double = 0.26
    }

    static let standardEase = Animation.timingCurve(0.2, 0, 0.2, 1, duration: Duration.base)

    /// Reading measure cap (§51).
    static let readingMeasure: CGFloat = 680
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
