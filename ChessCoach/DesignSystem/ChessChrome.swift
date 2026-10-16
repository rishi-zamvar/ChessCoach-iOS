import SwiftUI

/// chess.com-style dark chrome used around the board on game screens.
/// Menus/lists keep the Apothecary `Palette`; board screens use these.
enum ChessChrome {
    static let background = Color(hex: 0x302E2B)
    static let bar = Color(hex: 0x262421)
    static let card = Color(hex: 0x3C3A37)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xBABABA)
    /// Running clock: light background, dark text.
    static let clockActiveBG = Color.white
    static let clockActiveText = Color(hex: 0x262421)
    /// Idle clock: dark background, light text.
    static let clockIdleBG = Color(hex: 0x3C3A37)
    static let clockIdleText = Color(hex: 0xBABABA)
    static let lowTime = Color(hex: 0xE02828)
    static let accentGreen = Color(hex: 0x81B64C)
}

extension Color {
    /// `Color(hex: 0x302E2B)` — 24-bit RGB, opaque unless `alpha` given.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
