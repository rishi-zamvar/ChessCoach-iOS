import SwiftUI
import UIKit

/// Knightlight type (spec W9). Every font is an iOS text style, so it follows Dynamic Type and Bold
/// Text. New York (system serif) carries headers and the coach's voice; SF Pro does the UI.
enum Typography {
  // MARK: - Editorial (serif)
  /// Big numbers (rating). Scales with Dynamic Type from a 64 pt base.
  // ponytail: scaled once per launch (UIFontMetrics), so a text-size change applies on next launch; @ScaledMetric if it matters.
  static let heroNumber = scaledSerif(64, .medium, relativeTo: .largeTitle)
  static let weightLarge = heroNumber
  /// Page hero ("Today", "Train").
  static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
  /// Section titles.
  static let title = Font.system(.title2, design: .serif).weight(.semibold)
  /// Card titles.
  static let titleSmall = Font.system(.title3, design: .serif).weight(.semibold)
  /// The coach speaking.
  static let coachSpeech = Font.system(.body, design: .serif)

  // MARK: - UI (SF Pro)
  static let heading = Font.headline
  static let body = Font.body
  static let bodyEmph = Font.body.weight(.semibold)
  static let callout = Font.callout
  static let meta = Font.subheadline
  static let caption = Font.caption
  static let numeric = Font.title3.monospacedDigit().weight(.semibold)
  static let moveSAN = Font.body.monospaced()
  static let mono = Font.callout.monospaced()

  /// Tiny tracked-uppercase label above a section.
  static let eyebrow = Font.caption2.weight(.semibold)

  /// SF Symbols and big glyphs: a point size that still scales with Dynamic Type.
  static func symbol(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
    .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight, design: design)
  }

  private static func scaledSerif(_ size: CGFloat, _ weight: UIFont.Weight, relativeTo style: UIFont.TextStyle) -> Font {
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    let serif = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: serif))
  }
}

extension Text {
  /// Apply the eyebrow treatment in one go.
  func eyebrowStyle(_ color: Color = Palette.textTertiary) -> some View {
    self
      .font(Typography.eyebrow)
      .tracking(1.4)
      .textCase(.uppercase)
      .foregroundStyle(color)
  }
}
