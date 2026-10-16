import SwiftUI

/// Type system pairs a system-serif display with SF Pro Rounded body.
/// Serif gives editorial weight to headings + numbers (the "voice of the coach"
/// at rest); rounded keeps action UI soft + legible mid-set.
///
/// Two registers:
///   Editorial — serif, generous tracking, low frequency. Hero numbers, page titles, eyebrow.
///   UI — rounded sans, dense, high frequency. Body, buttons, captions.
enum Typography {
    // MARK: - Editorial (serif)
    /// Hero numbers — the weight in lb, the set count. Visible across the room.
    static let heroNumber = Font.system(size: 92, weight: .medium, design: .serif).italic()
    /// Big number for live workout — slightly more restrained than heroNumber.
    static let weightLarge = Font.system(size: 76, weight: .medium, design: .serif)
    /// Page hero ("Today", "Let's calibrate", "What happened?").
    static let display = Font.system(size: 44, weight: .regular, design: .serif).italic()
    /// Section title within a screen.
    static let title = Font.system(size: 30, weight: .regular, design: .serif)
    /// Card titles + medium headings.
    static let titleSmall = Font.system(size: 22, weight: .medium, design: .serif)

    // MARK: - UI (rounded)
    /// Inline headings inside cards (e.g. exercise names mid-flow).
    static let heading = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular, design: .rounded)
    static let bodyEmph = Font.system(size: 16, weight: .medium, design: .rounded)
    static let callout = Font.system(size: 14, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
    static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)

    // MARK: - Eyebrow (tracked uppercase)
    /// Tiny label above a section — "TODAY · MAY 26" feel. Always paired with
    /// `.tracking(1.6)` and `.textCase(.uppercase)` via `eyebrowStyle()`.
    static let eyebrow = Font.system(size: 11, weight: .semibold, design: .rounded)
}

extension Text {
    /// Apply the eyebrow treatment in one go.
    func eyebrowStyle(_ color: Color = Palette.textMuted) -> some View {
        self
            .font(Typography.eyebrow)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
