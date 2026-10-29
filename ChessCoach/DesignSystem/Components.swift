import SwiftUI

/// Knightlight Paper components (spec W9). One of each: screens compose these instead of
/// styling their own buttons, cards and badges.

// MARK: - Card

struct Card<Content: View>: View {
  let content: Content
  var padding: CGFloat = Spacing.l
  @Environment(\.colorScheme) private var scheme

  init(padding: CGFloat = Spacing.l, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(padding)
    .background(Palette.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
        .stroke(Palette.border, lineWidth: 0.75)
    )
    // Light mode only: in dark, raised surfaces read as lighter instead.
    .shadow(color: scheme == .dark ? .clear : Palette.ink.opacity(0.06), radius: 3, x: 0, y: 1)
  }
}

// MARK: - Buttons

/// The main action: an ink capsule, full width. At most one per screen.
struct PrimaryButton: View {
  let title: String
  let action: () -> Void
  var isLoading: Bool = false
  var icon: String? = nil

  var body: some View {
    Button(action: { Haptics.medium(); action() }) {
      HStack(spacing: Spacing.s) {
        if isLoading {
          ProgressView().controlSize(.small).tint(Palette.actionLabel)
        } else if let icon {
          Image(systemName: icon).font(Typography.callout.weight(.semibold))
        }
        Text(title).font(Typography.bodyEmph)
      }
      .frame(maxWidth: .infinity, minHeight: 50)
      .padding(.horizontal, Spacing.xl)
      .foregroundStyle(Palette.actionLabel)
      .background(Capsule().fill(Palette.action))
      .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle())
    .disabled(isLoading)
  }
}

/// A secondary action: outlined capsule.
struct SecondaryButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.light(); action() }) {
      Text(title)
        .font(Typography.bodyEmph)
        .frame(maxWidth: .infinity, minHeight: 50)
        .foregroundStyle(Palette.textPrimary)
        .background(Capsule().fill(Palette.surfaceRaised))
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle())
  }
}

/// Board-screen and card actions in a row (Retry / Next, Take back / Continue): ink when prominent,
/// outlined otherwise. Icon-only when `title` is empty (then `label` names it for VoiceOver).
struct ActionButton: View {
  let title: String
  var systemImage: String? = nil
  var prominent = false
  var label: String? = nil
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.light(); action() }) {
      HStack(spacing: 6) {
        if let systemImage { Image(systemName: systemImage).font(Typography.callout.weight(.bold)) }
        if !title.isEmpty { Text(title).font(Typography.bodyEmph) }
      }
      .frame(maxWidth: .infinity, minHeight: 46)
      .padding(.horizontal, Spacing.s)
      .foregroundStyle(prominent ? Palette.actionLabel : Palette.textPrimary)
      .background(Capsule().fill(prominent ? Palette.action : Palette.surfaceRaised))
      .overlay(Capsule().strokeBorder(prominent ? .clear : Palette.border, lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle())
    .accessibilityLabel(title.isEmpty ? (label ?? systemImage ?? "") : title)
  }
}

/// A round icon button that floats over content (board controls, sheet chrome): glass on iOS 26.
struct GlassIconButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.light(); action() }) {
      Image(systemName: systemImage)
        .font(Typography.body.weight(.semibold))
        .foregroundStyle(Palette.textPrimary)
        .frame(width: 44, height: 44)
    }
    .glassCircle()
    .accessibilityLabel(label)
  }
}

extension View {
  /// Liquid Glass on iOS 26 (navigation layer only); an opaque raised circle before that.
  @ViewBuilder func glassCircle() -> some View {
    if #available(iOS 26, *) {
      self.glassEffect(.regular.interactive(), in: Circle())
    } else {
      self.background(Circle().fill(Palette.surfaceRaised)).overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.75))
    }
  }

  /// Liquid Glass capsule for floating control clusters (board controls).
  @ViewBuilder func glassCapsule() -> some View {
    if #available(iOS 26, *) {
      self.glassEffect(.regular, in: Capsule())
    } else {
      self.background(Capsule().fill(Palette.surfaceRaised)).overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.75))
    }
  }
}

/// Slight press feedback, skipped under Reduce Motion.
struct PressableStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.85 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : AnimationToken.quick, value: configuration.isPressed)
  }
}

// MARK: - Chip

struct Chip: View {
  let title: String
  var isSelected: Bool = false
  var color: Color = Palette.action
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.selection(); action() }) {
      Text(title)
        .font(Typography.callout)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .foregroundStyle(isSelected ? Palette.actionLabel : Palette.textPrimary)
        .background(isSelected ? color : Palette.surfaceRaised)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? .clear : Palette.border, lineWidth: 0.75))
    }
    .buttonStyle(PressableStyle())
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Labels

/// Tracked-uppercase tiny label — set above a section title or hero number.
struct Eyebrow: View {
  let text: String
  var color: Color = Palette.textTertiary

  var body: some View {
    Text(text).eyebrowStyle(color)
  }
}

/// Editorial section head: eyebrow + serif title + optional subtitle.
struct SectionHeader: View {
  let title: String
  var eyebrow: String? = nil
  var subtitle: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      if let eyebrow { Eyebrow(text: eyebrow) }
      Text(title).font(Typography.title).foregroundStyle(Palette.textPrimary)
      if let subtitle {
        Text(subtitle).font(Typography.callout).foregroundStyle(Palette.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// A move-quality badge: glyph + colour, never colour alone.
struct QualityBadge: View {
  let quality: MoveQuality
  var showsTitle = false

  var body: some View {
    HStack(spacing: 6) {
      Text(quality.glyph)
        .font(Typography.caption.weight(.heavy).monospaced())
        .foregroundStyle(.white)
        .frame(minWidth: 22, minHeight: 20)
        .padding(.horizontal, 3)
        .background(Capsule().fill(quality.color))
      if showsTitle { Text(quality.title).font(Typography.caption).foregroundStyle(Palette.textPrimary) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(quality.title)
  }
}

// MARK: - Stepper (Play: Stockfish level)

/// 44x44 circular +/- step button.
struct StepperButton: View {
  enum Direction {
    case minus, plus
    var icon: String { self == .minus ? "minus" : "plus" }
  }
  let direction: Direction
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.light()
      action()
    } label: {
      Image(systemName: direction.icon)
        .font(Typography.body.weight(.semibold))
        .frame(width: 44, height: 44)
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.surfaceRaised)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.75))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(direction == .minus ? "Lower" : "Higher")
  }
}

// MARK: - Empty State

struct EmptyState: View {
  let title: String
  let message: String
  var systemImage: String = "leaf"

  var body: some View {
    VStack(spacing: Spacing.l) {
      Image(systemName: systemImage)
        .font(Typography.display.weight(.light))
        .foregroundStyle(Palette.sage.opacity(0.7))
        .accessibilityHidden(true)
      Text(title).font(Typography.titleSmall).foregroundStyle(Palette.textPrimary)
      Text(message)
        .font(Typography.body)
        .foregroundStyle(Palette.textSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(Spacing.xxl)
    .frame(maxWidth: .infinity)
  }
}
