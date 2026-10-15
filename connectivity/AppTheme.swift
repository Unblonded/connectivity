//
//  AppTheme.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import SwiftUI

/// Core design tokens. Everything visual in the app pulls from here so the
/// whole surface stays consistent when a value changes.
enum AppTheme {

    // MARK: Surfaces

    /// Base canvas. Deep, slightly blue night tone.
    static let bg = Color(red: 0.043, green: 0.075, blue: 0.094)
    /// Darker tone used at the top of background gradients.
    static let bgDeep = Color(red: 0.016, green: 0.035, blue: 0.055)
    /// Raised surface behind glass where extra opacity is needed.
    static let panel = Color(red: 0.059, green: 0.102, blue: 0.133)

    // MARK: Accents

    static let accent = Color(red: 0.490, green: 0.827, blue: 0.988)
    static let accentDeep = Color(red: 0.149, green: 0.655, blue: 0.914)
    static let muted = Color(red: 0.624, green: 0.702, blue: 0.788)

    /// Colors for the soft light blooms that sit *behind* glass surfaces.
    /// Liquid Glass only reads as glass when there is something to refract.
    static let aurora1 = Color(red: 0.149, green: 0.655, blue: 0.914)
    static let aurora2 = Color(red: 0.655, green: 0.545, blue: 0.980)
    static let aurora3 = Color(red: 0.176, green: 0.831, blue: 0.749)

    // MARK: Semantic

    static let good = Color(red: 0.09, green: 0.78, blue: 0.48)
    static let warn = Color(red: 1.00, green: 0.60, blue: 0.30)
    static let bad = Color(red: 1.00, green: 0.42, blue: 0.42)

    /// Single-pixel separator that reads correctly on top of glass.
    static let hairline = Color.white.opacity(0.10)

    // MARK: Gradients

    static let accentGradient = LinearGradient(
        colors: [accent, aurora2],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The red -> orange -> green scale used by the legend and score bars.
    static let signalGradient = LinearGradient(
        colors: [bad, warn, good],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension Font {
    /// Rounded display face used for titles and numerics.
    static func ds(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Monospaced face for live telemetry, so digits do not jitter.
    static func dsMono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Short human label for a 0...100 signal score.
func scoreDescriptor(_ score: Int) -> String {
    switch score {
    case 85...: return "Excellent"
    case 65..<85: return "Good"
    case 40..<65: return "Fair"
    case 15..<40: return "Weak"
    default: return "Dead zone"
    }
}
