import Foundation

/// A trainable skill: a node of the curriculum taxonomy (research 01 §1.2) mapped to
/// Lichess puzzle themes, or to a generated drill kind.
public struct Skill: Identifiable, Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    case puzzles([String])
    case drill(DrillKind)
  }

  public let id: String
  public let name: String
  public let summary: String
  public let source: Source
  /// Rating band this skill belongs to (suggested from `band.lowerBound`).
  public let band: ClosedRange<Int>
  /// Rough share of real games at the 400–1400 level where this motif decides things (0…1).
  public let frequency: Double
  public let systemImage: String

  public var themes: [String] {
    if case .puzzles(let tags) = source { return tags }
    return []
  }
}

public enum DrillKind: String, Codable, Hashable, Sendable, CaseIterable {
  case coordinates, checksCaptures, safeMove
}

public enum SkillCatalog {
  public static let all: [Skill] = [
    Skill(id: "A1", name: "Board vision", summary: "Name squares instantly.", source: .drill(.coordinates),
      band: 0...800, frequency: 0.3, systemImage: "square.grid.3x3"),
    Skill(id: "D1", name: "Blunder check", summary: "Checks, captures, threats — every move.", source: .drill(.safeMove),
      band: 0...1600, frequency: 1.0, systemImage: "shield.lefthalf.filled"),
    Skill(id: "D2", name: "Checks & captures", summary: "See all forcing moves at a glance.", source: .drill(.checksCaptures),
      band: 0...1200, frequency: 0.7, systemImage: "scope"),
    Skill(id: "C1", name: "Free pieces", summary: "Take what's hanging; don't hang yours.", source: .puzzles(["hangingPiece"]),
      band: 0...1000, frequency: 0.9, systemImage: "gift"),
    Skill(id: "B1", name: "Mate in one", summary: "Find the checkmate.", source: .puzzles(["mateIn1"]),
      band: 0...1000, frequency: 0.8, systemImage: "crown"),
    Skill(id: "C2", name: "Forks", summary: "One piece, two targets.", source: .puzzles(["fork"]),
      band: 300...1300, frequency: 0.8, systemImage: "arrow.triangle.branch"),
    Skill(id: "B3", name: "Back-rank mate", summary: "The king trapped behind its own pawns.", source: .puzzles(["backRankMate"]),
      band: 400...1300, frequency: 0.5, systemImage: "rectangle.bottomthird.inset.filled"),
    Skill(id: "C3", name: "Pins", summary: "Freeze a piece in front of a bigger one.", source: .puzzles(["pin"]),
      band: 500...1400, frequency: 0.6, systemImage: "pin"),
    Skill(id: "B4", name: "Mate in two", summary: "A forcing move, then mate.", source: .puzzles(["mateIn2"]),
      band: 600...1500, frequency: 0.5, systemImage: "crown.fill"),
    Skill(id: "C4", name: "Skewers", summary: "Attack through the big piece.", source: .puzzles(["skewer"]),
      band: 600...1500, frequency: 0.3, systemImage: "arrow.right.to.line"),
    Skill(id: "C5", name: "Discovered attacks", summary: "Move one piece, unleash another.",
      source: .puzzles(["discoveredAttack", "discoveredCheck", "doubleCheck"]), band: 700...1600, frequency: 0.4,
      systemImage: "rays"),
    Skill(id: "B5", name: "Mating patterns", summary: "Smothered, Anastasia, Arabian and friends.",
      source: .puzzles(["smotheredMate", "anastasiaMate", "arabianMate", "bodenMate", "hookMate", "doubleBishopMate"]),
      band: 700...1600, frequency: 0.3, systemImage: "sparkles"),
    Skill(id: "C6", name: "Remove the defender", summary: "Take away the guard.", source: .puzzles(["capturingDefender"]),
      band: 800...1600, frequency: 0.3, systemImage: "person.badge.minus"),
    Skill(id: "C7", name: "Deflection & decoy", summary: "Drag pieces where you want them.", source: .puzzles(["deflection", "attraction"]),
      band: 900...1700, frequency: 0.3, systemImage: "arrow.uturn.right"),
    Skill(id: "C9", name: "Trapped pieces", summary: "Win pieces with nowhere to go.", source: .puzzles(["trappedPiece"]),
      band: 800...1600, frequency: 0.2, systemImage: "lock"),
    Skill(id: "C13", name: "Promotion", summary: "Push, promote, win.", source: .puzzles(["promotion", "advancedPawn"]),
      band: 600...1500, frequency: 0.3, systemImage: "arrow.up.circle"),
    Skill(id: "E1", name: "Pawn endgames", summary: "Opposition, square, key squares.", source: .puzzles(["pawnEndgame"]),
      band: 700...1600, frequency: 0.3, systemImage: "figure.walk"),
    Skill(id: "E8", name: "Rook endgames", summary: "The most common endgame.", source: .puzzles(["rookEndgame"]),
      band: 900...1800, frequency: 0.3, systemImage: "building.columns"),
  ]

  public static func skill(_ id: String) -> Skill? { all.first { $0.id == id } }

  /// Skills worth suggesting at `rating` (the band starts at or below it, with one band of headroom).
  public static func suggested(forRating rating: Int) -> [Skill] {
    all.filter { $0.band.lowerBound <= rating + 200 }
  }

  /// The skill a game motif or mistake trains.
  public static func skill(forMotif motif: Motif) -> String? {
    switch motif {
    case .fork: "C2"
    case .pin: "C3"
    case .skewer: "C4"
    case .discoveredAttack: "C5"
    case .backRankMate: "B3"
    case .mate: "B1"
    case .mateThreat: "B4"
    case .winsMaterial, .hangingPiece: "C1"
    case .promotion: "C13"
    case .check: nil
    }
  }

  public static func skill(forMistake type: MistakeType, phase: GamePhaseKind) -> String {
    switch type {
    case .hungMaterial, .allowedTactic: "D1"
    case .endgameError: "E1"
    case .missedTactic: "D2"
    case .failedConversion: phase == .endgame ? "E1" : "C1"
    case .positional: "D1"
    }
  }
}
