import SwiftUI

/// Motion tokens. Screens skip animation entirely under Reduce Motion.
enum AnimationToken {
  /// Press feedback, toggles.
  static let quick: Animation = .spring(response: 0.28, dampingFraction: 0.85)
  /// Banners, cards appearing.
  static let medium: Animation = .spring(response: 0.45, dampingFraction: 0.82)
  /// A piece sliding to its square (spec W9: 180 ms ease-out).
  static let pieceMove: Animation = .easeOut(duration: 0.18)
}
