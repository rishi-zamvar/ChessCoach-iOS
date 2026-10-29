import Foundation

/// Forgiving streaks (spec W6): any day you finish something counts, and one missed day a week
/// is frozen for free, so a single busy day doesn't wipe out a habit.
public enum StreakCounter {
  public static func count(practiced: Set<Date>, now: Date, calendar: Calendar = .current) -> Int {
    let days = Set(practiced.map { calendar.startOfDay(for: $0) })
    var day = calendar.startOfDay(for: now)
    if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
    var count = 0
    var frozenWeeks: Set<Int> = []
    while true {
      if days.contains(day) {
        count += 1
      } else {
        let week = calendar.component(.weekOfYear, from: day) + 100 * calendar.component(.yearForWeekOfYear, from: day)
        let before = calendar.date(byAdding: .day, value: -1, to: day)!
        // A gap is frozen only if it's a single day with practice either side, once per week.
        guard count > 0, !frozenWeeks.contains(week), days.contains(before) else { break }
        frozenWeeks.insert(week)
      }
      day = calendar.date(byAdding: .day, value: -1, to: day)!
    }
    return count
  }
}

/// How often the app may ask you something (thumbs, surveys): one prompt a session, none during
/// timed play, and a 30-day pause after two dismissals in a row (spec W8).
public struct PromptBudget: Codable, Equatable, Sendable {
  public var shownThisSession = false
  public var dismissStreak = 0
  public var pausedUntil: Date?

  public init() {}

  public func mayShow(now: Date, timedPlay: Bool) -> Bool {
    if timedPlay || shownThisSession { return false }
    if let pausedUntil, now < pausedUntil { return false }
    return true
  }

  public mutating func shown(now: Date) { shownThisSession = true }

  public mutating func dismissed(now: Date) {
    dismissStreak += 1
    if dismissStreak >= 2 {
      pausedUntil = now.addingTimeInterval(30 * 86_400)
      dismissStreak = 0
    }
  }

  public mutating func answered() { dismissStreak = 0 }
  public mutating func newSession() { shownThisSession = false }
}

/// When to show the App Store rating sheet (spec W8): after a success moment, once per version,
/// 7+ days after install, never within a day of a thumbs-down or a bug report.
public struct ReviewPromptPolicy: Codable, Equatable, Sendable {
  public var installedAt: Date
  public var askedVersions: Set<String> = []
  public var lastNegative: Date?

  public init(installedAt: Date) {
    self.installedAt = installedAt
  }

  public func shouldAsk(version: String, now: Date) -> Bool {
    guard now.timeIntervalSince(installedAt) >= 7 * 86_400, !askedVersions.contains(version) else { return false }
    if let lastNegative, now.timeIntervalSince(lastNegative) < 86_400 { return false }
    return true
  }

  public mutating func asked(version: String) { askedVersions.insert(version) }
  public mutating func negativeSignal(now: Date) { lastNegative = now }
}
