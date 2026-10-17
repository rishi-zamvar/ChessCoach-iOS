import SwiftUI

/// Apothecary editorial palette. Pale lavender canvas, warm paper-cream cards,
/// sage primary, dusty rose accent, deep ink (warmer than pure charcoal).
///
/// Two background layers stack: the lavender canvas is the room, the cream
/// card is the page. Atmosphere (grain + mesh blobs) lives between them.
enum Palette {
    // MARK: - Atmosphere (canvas + cards)
    /// Pale lavender canvas — never used as a flat solid in production; always
    /// rendered through `BackgroundAtmosphere` so grain + mesh blobs sit on top.
    static let canvas = Color(light: Color(red: 0.965, green: 0.955, blue: 0.985), dark: Color(red: 0.1, green: 0.095, blue: 0.115))
    /// Legacy alias kept so existing call sites still compile.
    static let background = canvas
    /// Warm paper cream — what every card sits on. Slightly off-white toward
    /// cream so the lavender canvas reads as the cooler base.
    static let paper = Color(light: Color(red: 0.992, green: 0.984, blue: 0.965), dark: Color(red: 0.155, green: 0.148, blue: 0.145))
    /// Legacy alias.
    static let surface = paper
    /// Pale sage tint for inset surfaces (chips, secondary buttons).
    static let surfaceAlt = Color(light: Color(red: 0.945, green: 0.955, blue: 0.935), dark: Color(red: 0.19, green: 0.205, blue: 0.19))

    // MARK: - Brand
    static let primary = Color(red: 0.62, green: 0.74, blue: 0.65)
    static let primaryDeep = Color(light: Color(red: 0.36, green: 0.50, blue: 0.42), dark: Color(red: 0.36, green: 0.55, blue: 0.44))
    static let accent = Color(red: 0.92, green: 0.74, blue: 0.74)
    static let accentDeep = Color(light: Color(red: 0.74, green: 0.50, blue: 0.50), dark: Color(red: 0.9, green: 0.66, blue: 0.66))

    // MARK: - Ink (text)
    /// Warm soft ink — used everywhere instead of pure charcoal. Reads softer
    /// against cream paper than a cool charcoal does.
    static let ink = Color(light: Color(red: 0.20, green: 0.17, blue: 0.16), dark: Color(red: 0.95, green: 0.93, blue: 0.9))
    /// Legacy alias.
    static let textPrimary = ink
    static let textSecondary = Color(light: Color(red: 0.46, green: 0.42, blue: 0.40), dark: Color(red: 0.74, green: 0.71, blue: 0.68))
    static let textMuted = Color(light: Color(red: 0.62, green: 0.58, blue: 0.55), dark: Color(red: 0.56, green: 0.53, blue: 0.5))
    static let textOnDark = Color(red: 0.992, green: 0.984, blue: 0.965)

    // MARK: - Semantic
    static let success = Color(red: 0.56, green: 0.72, blue: 0.58)
    static let warning = Color(red: 0.92, green: 0.78, blue: 0.55)
    static let danger = Color(red: 0.84, green: 0.55, blue: 0.55)

    // MARK: - Felt tag (workout-specific)
    static let feltEasy = Color(light: Color(red: 0.72, green: 0.85, blue: 0.74), dark: Color(red: 0.3, green: 0.45, blue: 0.33))
    static let feltRight = Color(red: 0.62, green: 0.74, blue: 0.65)
    static let feltHard = Color(red: 0.94, green: 0.82, blue: 0.60)
    static let feltPartial = Color(red: 0.92, green: 0.74, blue: 0.74)  // dusty rose
    static let feltFailed = Color(red: 0.88, green: 0.60, blue: 0.60)

    // MARK: - Borders + dividers (hairline)
    /// Warm hairline border — always 1pt; never bolder.
    static let border = Color(light: Color(red: 0.86, green: 0.84, blue: 0.80), dark: Color(red: 0.28, green: 0.27, blue: 0.26))
    static let divider = Color(light: Color(red: 0.90, green: 0.88, blue: 0.84), dark: Color(red: 0.23, green: 0.22, blue: 0.21))

    // MARK: - Atmosphere helpers
    /// First mesh blob — sage, warm side of top-leading.
    static let meshSage = Color(light: Color(red: 0.72, green: 0.84, blue: 0.74).opacity(0.55), dark: Color(red: 0.3, green: 0.42, blue: 0.33).opacity(0.35))
    /// Second mesh blob — dusty rose, cooler bottom-trailing.
    static let meshRose = Color(light: Color(red: 0.94, green: 0.80, blue: 0.82).opacity(0.45), dark: Color(red: 0.42, green: 0.28, blue: 0.31).opacity(0.3))
    /// Grain ink — near-black at very low alpha, applied as overlay noise.
    static let grainInk = Color(light: Color(red: 0.18, green: 0.15, blue: 0.13), dark: Color(red: 0.95, green: 0.93, blue: 0.9))
}
