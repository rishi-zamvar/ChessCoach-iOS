import SwiftUI

/// ChessCoach mark — a serif knight glyph in a sage roundel.
struct LogoMark: View {
    var size: CGFloat = 48
    var tint: Color = Palette.primary

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Text("\u{265E}")
                .font(.system(size: size * 0.62, weight: .regular, design: .serif))
                .foregroundStyle(Palette.textOnDark)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Full wordmark with hand-drawn underline arc — used on splash, onboarding.
struct AppMark: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            LogoMark(size: 48, tint: Palette.primaryDeep)
            VStack(spacing: 2) {
                Text("ChessCoach")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .tracking(0.4)
                HandDrawnUnderline()
                    .stroke(Palette.primaryDeep.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .frame(width: 110, height: 6)
            }
        }
    }
}

/// A wobbly hand-drawn arc — soft signature beneath the wordmark.
struct HandDrawnUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: mid + 1.5))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: mid + 1.5),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: mid - 2.5),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: mid + 4.0)
        )
        return p
    }
}
