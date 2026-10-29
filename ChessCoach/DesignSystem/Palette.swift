import SwiftUI

/// Knightlight Paper (spec W9): warm paper surfaces, ink text, sage for the coach, rose for warmth.
/// Follows the system appearance; every token has a dark value and, where text sits on it, an
/// Increase Contrast value. Views use these names only (scripts/lint-design.sh enforces it).
enum Palette {
  // MARK: - Surfaces
  /// Every screen's background, board screens included.
  static let surfaceBase = Color(light: 0xF6F4EF, dark: 0x181715)
  /// Cards, sheets.
  static let surfaceRaised = Color(light: 0xFDFBF6, dark: 0x23211E)
  /// Inputs, wells, the move list.
  static let surfaceSunken = Color(light: 0xEFEBE3, dark: 0x100F0E)

  // MARK: - Text
  static let textPrimary = Color(light: 0x2B2523, dark: 0xF2EDE6, lightHC: 0x15110F, darkHC: 0xFFFFFF)
  static let textSecondary = Color(light: 0x6B625D, dark: 0xB5ADA5, lightHC: 0x4A433F, darkHC: 0xD8D1C9)
  static let textTertiary = Color(light: 0x8A8178, dark: 0x8F877F, lightHC: 0x5F5852, darkHC: 0xB5ADA5)

  // MARK: - Actions + accents
  /// The one main action on a screen: an ink capsule.
  static let action = textPrimary
  static let actionLabel = Color(light: 0xF6F4EF, dark: 0x181715)
  /// The coach's colour: rings, progress, links.
  static let sage = Color(light: 0x4F7560, dark: 0x8DB59C, lightHC: 0x36533F, darkHC: 0xB0D4BD)
  static let sageSoft = Color(light: 0xDDE7DF, dark: 0x2A3A30)
  /// Streak and warmth only.
  static let rose = Color(light: 0xB06F6F, dark: 0xE6A8A8, lightHC: 0x8A4E4E, darkHC: 0xF2C4C4)

  // MARK: - Status
  static let success = Color(light: 0x2F7D4F, dark: 0x5CC98A, lightHC: 0x1F5C38, darkHC: 0x8FE3B0)
  static let danger = Color(light: 0xB23A1E, dark: 0xFF7A52, lightHC: 0x8A2A12, darkHC: 0xFFA285)
  static let warning = Color(light: 0xA87F00, dark: 0xF0D24A, lightHC: 0x7A5C00, darkHC: 0xF7E38C)

  // MARK: - Lines
  static let border = Color(light: 0xDDD7CC, dark: 0x3A3733)
  static let divider = Color(light: 0xE7E1D7, dark: 0x2E2B28)

  // MARK: - Board extras (same in both modes: the board is content)
  static let evalWhite = Color(light: 0xF4F1EA, dark: 0xE9E4DA)
  static let evalBlack = Color(light: 0x2A2724, dark: 0x2A2724)
  static let separatorStrong = Color(light: Color(hex: 0x2B2523, alpha: 0.25), dark: Color(hex: 0xF2EDE6, alpha: 0.25))
  static let check = Color(hex: 0xE5383B)

  // MARK: - Clocks (games)
  static let clockActiveBG = textPrimary
  static let clockActiveText = actionLabel
  static let clockIdleBG = surfaceSunken
  static let clockIdleText = textSecondary

  // MARK: - Atmosphere (hubs only, half strength)
  static let meshSage = Color(light: Color(hex: 0xB8D6BD, alpha: 0.28), dark: Color(hex: 0x4D6B55, alpha: 0.18))
  static let meshRose = Color(light: Color(hex: 0xF0CCD1, alpha: 0.22), dark: Color(hex: 0x6B4750, alpha: 0.15))
  static let grainInk = Color(light: 0x2E2621, dark: 0xF2EDE6)

  // MARK: - Legacy names (older call sites; new code uses the names above)
  static let canvas = surfaceBase
  static let background = surfaceBase
  static let paper = surfaceRaised
  static let surface = surfaceRaised
  static let surfaceAlt = surfaceSunken
  static let ink = textPrimary
  static let textMuted = textTertiary
  static let textOnDark = actionLabel
  static let primary = sage
  static let primaryDeep = sage
  static let accent = rose
  static let accentDeep = rose
}

/// Move quality: colour-blind-safe (Okabe-Ito based) and always shown with its glyph.
enum MoveQuality: String, CaseIterable {
  case brilliant, great, best, good, book, inaccuracy, mistake, blunder, miss

  var glyph: String {
    switch self {
    case .brilliant: "!!"
    case .great: "!"
    case .best: "★"
    case .good: "✓"
    case .book: "B"
    case .inaccuracy: "?!"
    case .mistake: "?"
    case .blunder: "??"
    case .miss: "✕"
    }
  }

  var title: String { rawValue.capitalized }

  var color: Color {
    switch self {
    case .brilliant: Color(light: 0x00897B, dark: 0x3CC9B8)
    case .great: Color(light: 0x0072B2, dark: 0x56B4E9)
    case .best: Color(light: 0x2F7D4F, dark: 0x5CC98A)
    case .good: Color(light: 0x6B7F70, dark: 0x93A898)
    case .book: Color(light: 0x8C6E4E, dark: 0xC2A07C)
    case .inaccuracy: Color(light: 0xA87F00, dark: 0xF0D24A)
    case .mistake: Color(light: 0xD9730D, dark: 0xF5A04A)
    case .blunder: Color(light: 0xC0392B, dark: 0xFF6B5B)
    case .miss: Color(light: 0xCC79A7, dark: 0xE7A3CC)
    }
  }
}
