import SwiftUI

/// "Who played what, and why" as a small chat-style card: avatar, name, the move as a
/// chip, then the reason in readable type.
struct MoveNote: View {
  let who: String
  let isYou: Bool
  let san: String
  let text: String
  var compact = false

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      ZStack {
        Circle().fill(isYou ? Palette.sage.opacity(0.22) : Color.primary.opacity(0.08))
        Image(systemName: isYou ? "person.fill" : "cpu")
          .font(.system(.footnote).weight(.semibold))
          .foregroundStyle(isYou ? Palette.sage : Palette.textSecondary)
      }
      .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(who.uppercased())
            .font(.system(.caption2).weight(.heavy)).tracking(0.8)
            .foregroundStyle(Palette.textSecondary)
          Text(san)
            .font(.system(.footnote).weight(.bold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(isYou ? Palette.sage.opacity(0.35) : Color.primary.opacity(0.14)))
        }
        Text(Self.body(text, san: san))
          .font((compact ? Font.callout : Font.subheadline).weight(.medium))
          .foregroundStyle(Palette.textPrimary.opacity(0.92))
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
    .accessibilityElement(children: .combine)
  }

  /// "Bb5 attacks the knight on c6." → "Attacks the knight on c6." (the move is already in the chip).
  static func body(_ text: String, san: String) -> String {
    var rest = Substring(text)
    if rest.hasPrefix(san) { rest = rest.dropFirst(san.count) }
    rest = rest.drop { $0 == " " || $0 == "." }
    guard let first = rest.first else { return text }
    return first.uppercased() + rest.dropFirst()
  }
}

/// The coach in your corner, as a speech bubble with a replay button.
struct CoachLineBubble: View {
  var headline: String?
  let text: String
  var speaking = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var onReplay: (() -> Void)?

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text("♞")
        .font(.system(.title2, design: .serif))
        .foregroundStyle(Palette.surfaceBase)
        .frame(width: 38, height: 38)
        .background(Circle().fill(Palette.sage))
        .shadow(color: Palette.sage.opacity(speaking ? 0.7 : 0), radius: speaking ? 8 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: speaking)
      VStack(alignment: .leading, spacing: 2) {
        Text("COACH")
          .font(.system(.caption2).weight(.heavy)).tracking(1)
          .foregroundStyle(Palette.sage)
        if let headline {
          Text(headline)
            .font(.system(.footnote).weight(.bold))
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(text)
          .font(.system(.body, design: .serif).weight(.semibold))
          .italic()
          .foregroundStyle(Palette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      if let onReplay {
        Button(action: onReplay) {
          Image(systemName: "speaker.wave.2.fill")
            .font(.system(.subheadline).weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Say it again")
      }
    }
    .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Palette.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.sage.opacity(0.45), lineWidth: 1)))
    .padding(.horizontal, Spacing.m)
    .padding(.top, Spacing.xs)
    .accessibilityIdentifier("coach-bubble")
  }
}
