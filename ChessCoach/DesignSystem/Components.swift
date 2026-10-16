import SwiftUI

/// Reusable primitives in the apothecary-editorial system. Paper-cream cards,
/// hairline borders, soft press states. Animations are always springs.

// MARK: - Card

struct Card<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.l

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
        .background(Palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.75)
        )
        .shadow(color: Palette.ink.opacity(0.04), radius: 14, x: 0, y: 4)
    }
}

// MARK: - Primary Button (paper-pressed depth)

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var icon: String? = nil
    @State private var pressed = false

    var body: some View {
        Button(action: { Haptics.medium(); action() }) {
            HStack(spacing: Spacing.s) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.textOnDark)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(Typography.bodyEmph)
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.l)
            .padding(.horizontal, Spacing.xl)
            .foregroundStyle(Palette.textOnDark)
            .background(
                ZStack {
                    Palette.primaryDeep
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous)
                    .stroke(Palette.ink.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Palette.primaryDeep.opacity(pressed ? 0.05 : 0.20), radius: pressed ? 4 : 12, x: 0, y: pressed ? 1 : 6)
            .scaleEffect(pressed ? 0.98 : 1.0)
        }
        .disabled(isLoading)
        .animation(AnimationToken.quick, value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            Text(title)
                .font(Typography.bodyEmph)
                .tracking(0.3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.l)
                .foregroundStyle(Palette.primaryDeep)
                .background(Palette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous)
                        .stroke(Palette.border, lineWidth: 0.75)
                )
        }
        .pulseOnTap()
    }
}

// MARK: - Chip

struct Chip: View {
    let title: String
    var isSelected: Bool = false
    var color: Color = Palette.primary
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Text(title)
                .font(Typography.callout)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .foregroundStyle(isSelected ? Palette.textOnDark : Palette.textPrimary)
                .background(isSelected ? color : Palette.paper)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? .clear : Palette.border, lineWidth: 0.75)
                )
        }
        .pulseOnTap()
    }
}

// MARK: - Eyebrow

/// Tracked-uppercase tiny label — set above a section title or hero number.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.textMuted

    var body: some View {
        Text(text).eyebrowStyle(color)
    }
}

// MARK: - Section Header (editorial: eyebrow + serif title + optional sub)

struct SectionHeader: View {
    let title: String
    var eyebrow: String? = nil
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let eyebrow {
                Eyebrow(text: eyebrow)
            }
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ornament Divider

/// Editorial ornament: hairline · diamond · hairline. Use between sections
/// where a plain divider would feel utilitarian.
struct OrnamentDivider: View {
    var tint: Color = Palette.border
    var dotTint: Color = Palette.primaryDeep

    var body: some View {
        HStack(spacing: Spacing.m) {
            Rectangle()
                .fill(tint)
                .frame(height: 0.75)
            Image(systemName: "diamond.fill")
                .font(.system(size: 6, weight: .regular))
                .foregroundStyle(dotTint.opacity(0.6))
            Rectangle()
                .fill(tint)
                .frame(height: 0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty State

/// 44x44 circular +/- step button. Used by Onboarding weight picker,
/// SwimSetLogSheet (distance + reps), CardioSetLogSheet (reps), and
/// SwimmingActiveView (laps). Single source of truth so the button
/// styling stays consistent + the call sites shrink.
struct StepperButton: View {
    enum Direction { case minus, plus
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
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Palette.primaryDeep)
                .background(Palette.paper)
                .clipShape(Circle())
                .overlay(Circle().stroke(Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Big mm:ss numeric input for set log sheets. Used by both Cardio + Swim
/// set log sheets. Optional binding — the Done toolbar accessory is the
/// caller's responsibility (they already attach one for the whole sheet).
struct TimeMinSecField: View {
    @Binding var minutes: String
    @Binding var seconds: String
    var label: String = "Time"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Eyebrow(text: label)
            HStack(spacing: Spacing.s) {
                numberField($minutes, placeholder: "0")
                Text(":").font(Typography.heroNumber).foregroundStyle(Palette.textMuted)
                numberField($seconds, placeholder: "00")
                Text("mm:ss")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.leading, Spacing.s)
            }
        }
    }

    private func numberField(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .keyboardType(.numberPad)
            .font(Typography.heroNumber)
            .multilineTextAlignment(.center)
            .frame(width: 90, height: 64)
            .background(Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous))
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "leaf"

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.primary.opacity(0.7))
            Text(title)
                .font(Typography.titleSmall)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
