import SwiftUI

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

  /// Follows the system appearance, and Increase Contrast when HC values are given.
  init(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
    self.init(uiColor: UIColor { traits in
      let high = traits.accessibilityContrast == .high
      let hex = traits.userInterfaceStyle == .dark ? (high ? darkHC ?? dark : dark) : (high ? lightHC ?? light : light)
      return UIColor(Color(hex: hex))
    })
  }

  init(light: Color, dark: Color) {
    self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
  }
}
