import SwiftUI

/// chess.com-style dark chrome used around the board on game screens.
/// Menus/lists keep the Apothecary `Palette`; board screens use these.
enum ChessChrome {
    static let background = Color(light: 0xEEEDEA, dark: 0x302E2B)
    static let bar = Color(light: 0xFFFFFF, dark: 0x262421)
    static let card = Color(light: 0xFFFFFF, dark: 0x3C3A37)
    static let textPrimary = Color(light: 0x262421, dark: 0xFFFFFF)
    static let textSecondary = Color(light: 0x6B6966, dark: 0xBABABA)
    /// Running clock: stands out from the chrome (light on dark, dark on light).
    static let clockActiveBG = Color(light: 0x262421, dark: 0xFFFFFF)
    static let clockActiveText = Color(light: 0xFFFFFF, dark: 0x262421)
    /// Idle clock: blends into the chrome.
    static let clockIdleBG = Color(light: 0xE3E1DD, dark: 0x3C3A37)
    static let clockIdleText = Color(light: 0x6B6966, dark: 0xBABABA)
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

extension Color {
    /// Follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}
