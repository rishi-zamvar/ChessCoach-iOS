import SwiftUI

/// Knightlight mark: a serif knight glyph in a sage roundel.
struct LogoMark: View {
  var size: CGFloat = 48
  var tint: Color = Palette.sage

  var body: some View {
    ZStack {
      Circle().fill(tint)
      Text("\u{265E}")
        .font(.system(size: size * 0.62, weight: .regular, design: .serif))
        .foregroundStyle(Palette.actionLabel)
        .offset(y: -size * 0.02)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
