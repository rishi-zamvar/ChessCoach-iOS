import ChessKit

/// Board colors as data (hex RGB). Overlays use the given alpha.
public struct BoardTheme: Identifiable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let light: UInt32
  public let dark: UInt32
  /// Last-move tint drawn over the square color.
  public let lastMove: UInt32
  public let lastMoveAlpha: Double
  /// Selected square / premove tint.
  public let selected: UInt32
  public let premove: UInt32

  public static let green = BoardTheme(
    id: "green", name: "Green", light: 0xEEEED2, dark: 0x769656,
    lastMove: 0xFFFF33, lastMoveAlpha: 0.5, selected: 0xFFFF33, premove: 0x5A8DC9)
  public static let brown = BoardTheme(
    id: "brown", name: "Brown", light: 0xF0D9B5, dark: 0xB58863,
    lastMove: 0xCDD26A, lastMoveAlpha: 0.75, selected: 0x14551E, premove: 0x5A8DC9)
  public static let blue = BoardTheme(
    id: "blue", name: "Blue", light: 0xDEE3E6, dark: 0x8CA2AD,
    lastMove: 0xC3D888, lastMoveAlpha: 0.8, selected: 0x14551E, premove: 0x5A8DC9)
  public static let walnut = BoardTheme(
    id: "walnut", name: "Walnut", light: 0xE9D4B4, dark: 0x8A6240,
    lastMove: 0xD9C25A, lastMoveAlpha: 0.6, selected: 0xD9C25A, premove: 0x5A8DC9)

  public static let all: [BoardTheme] = [.green, .brown, .blue, .walnut]
  public static let `default` = green

  public static func named(_ id: String) -> BoardTheme { all.first { $0.id == id } ?? .default }
}

/// Bundled piece sets (asset-catalog namespaces).
public enum PieceSetID: String, CaseIterable, Identifiable, Sendable {
  case staunty, cardinal, maestro, cburnett

  public var id: String { rawValue }
  public static let `default` = PieceSetID.staunty

  public var displayName: String { rawValue.capitalized }

  /// Asset name like `staunty/wN`.
  public func assetName(color: Piece.Color, kind: Piece.Kind) -> String {
    let c = color == .white ? "w" : "b"
    let k =
      switch kind {
      case .king: "K"
      case .queen: "Q"
      case .rook: "R"
      case .bishop: "B"
      case .knight: "N"
      case .pawn: "P"
      }
    return "\(rawValue)/\(c)\(k)"
  }
}
