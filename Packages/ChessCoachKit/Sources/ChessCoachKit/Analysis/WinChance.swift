import Foundation

/// Win-chance and accuracy formulas, re-implemented from the published Lichess
/// sources (lila `WinPercent` / `AccuracyPercent`). Win% is 0…100.
public enum WinChance {
  /// Win% for the side whose perspective `score` is from.
  public static func winPercent(_ score: EngineScore) -> Double {
    switch score {
    case .centipawns(let cp):
      let clamped = Double(max(-1000, min(1000, cp)))
      return 50 + 50 * (2 / (1 + exp(-0.00368208 * clamped)) - 1)
    case .mate(let n):
      // Mate for the side to move = certain win; getting mated = certain loss.
      return n > 0 ? 100 : 0
    }
  }

  /// Accuracy (0…100) of a move that took the mover's win% from `before` to `after`.
  public static func moveAccuracy(winBefore before: Double, winAfter after: Double) -> Double {
    if after >= before { return 100 }
    let raw = 103.1668100711649 * exp(-0.04354415386753951 * (before - after)) - 3.166924740191411
    return max(0, min(100, raw + 1))
  }

  /// Game accuracy for each side, Lichess-style: mean of a volatility-weighted mean and a
  /// harmonic mean of per-move accuracies.
  ///
  /// - parameter whiteWinPercents: White's win% for the start position and after every ply.
  /// - parameter whiteMovesFirst: false when the game started with Black to move.
  public static func gameAccuracy(whiteWinPercents: [Double], whiteMovesFirst: Bool = true) -> (white: Double?, black: Double?) {
    let all = whiteWinPercents
    guard all.count >= 2 else { return (nil, nil) }
    let moves = all.count - 1
    let windowSize = max(2, min(8, moves / 10))

    var windows: [[Double]] = Array(repeating: Array(all.prefix(windowSize)), count: max(0, windowSize - 2))
    if all.count >= windowSize {
      for start in 0...(all.count - windowSize) {
        windows.append(Array(all[start..<(start + windowSize)]))
      }
    }
    let weights = windows.map { max(0.5, min(12, standardDeviation($0))) }

    var white: [(accuracy: Double, weight: Double)] = []
    var black: [(accuracy: Double, weight: Double)] = []
    for i in 0..<moves {
      let prev = all[i]
      let next = all[i + 1]
      let weight = i < weights.count ? weights[i] : weights.last ?? 1
      let isWhite = (i % 2 == 0) == whiteMovesFirst
      if isWhite {
        white.append((moveAccuracy(winBefore: prev, winAfter: next), weight))
      } else {
        black.append((moveAccuracy(winBefore: 100 - prev, winAfter: 100 - next), weight))
      }
    }
    return (combine(white), combine(black))
  }

  static func combine(_ items: [(accuracy: Double, weight: Double)]) -> Double? {
    guard !items.isEmpty else { return nil }
    let weightSum = items.reduce(0) { $0 + $1.weight }
    let weighted = items.reduce(0) { $0 + $1.accuracy * $1.weight } / weightSum
    let harmonic = Double(items.count) / items.reduce(0) { $0 + 1 / max(1, $1.accuracy) }
    return (weighted + harmonic) / 2
  }

  static func standardDeviation(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let mean = xs.reduce(0, +) / Double(xs.count)
    let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
    return variance.squareRoot()
  }
}
