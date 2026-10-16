import Foundation

/// Ties the app's rating to the user's real chess.com rating, so the starting
/// point and the difficulty match how they actually play.
public enum RatingAnchor {
  /// Median of the user's own rating over their latest chess.com games, preferring
  /// the time class they play most recently (rapid, blitz, ...). Nil with no games.
  public static func realRating(_ games: [GameRecord], recent: Int = 10) -> Int? {
    let rated = games
      .filter { $0.source == .chesscom }
      .sorted { $0.startedAt > $1.startedAt }
      .compactMap { g -> (String?, Int)? in
        guard let elo = g.userColor == "white" ? g.whiteElo : g.blackElo else { return nil }
        return (g.timeClass, elo)
      }
    guard let latestClass = rated.first?.0 else { return rated.isEmpty ? nil : median(rated.prefix(recent).map(\.1)) }
    let same = rated.filter { $0.0 == latestClass }.prefix(recent).map(\.1)
    return median(same)
  }

  /// Starting rating: the real rating when known, nudged at most ±100 by placement.
  public static func blend(placement: Int, real: Int?) -> Int {
    guard let real else { return placement }
    return real + max(-100, min(100, placement - real))
  }

  /// True when the stored rating has drifted too far from the real one.
  public static func needsRecalibration(current: Int, real: Int?) -> Bool {
    guard let real else { return false }
    return abs(current - real) > 150
  }

  static func median(_ values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
  }
}
