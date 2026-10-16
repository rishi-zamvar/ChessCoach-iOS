import SwiftUI

struct TrainView: View {
  private let modes: [(title: String, blurb: String, icon: String, milestone: String)] = [
    ("Drills", "Mates, tactics, board vision. Adaptive daily set.", "bolt.circle", "M3"),
    ("Openings", "Learn your repertoire move by move.", "book.closed", "M3"),
    ("Play Coach", "A game where the coach watches every move.", "person.wave.2", "M4"),
  ]

  var body: some View {
    ZStack {
      BackgroundAtmosphere()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          Eyebrow(text: "Train")
          Text("Train")
            .font(Typography.display)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, Spacing.s)
          ForEach(modes, id: \.title) { mode in
            Button {
              ToastCenter.shared.show("\(mode.title) is coming in \(mode.milestone)")
            } label: {
              Card {
                HStack(alignment: .top, spacing: Spacing.m) {
                  Image(systemName: mode.icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Palette.primaryDeep)
                    .frame(width: 36)
                  VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(mode.title)
                      .font(Typography.titleSmall)
                      .foregroundStyle(Palette.ink)
                    Text(mode.blurb)
                      .font(Typography.callout)
                      .foregroundStyle(Palette.textSecondary)
                      .multilineTextAlignment(.leading)
                    Text("Coming in \(mode.milestone)")
                      .font(Typography.caption)
                      .foregroundStyle(Palette.primaryDeep)
                      .padding(.horizontal, Spacing.s)
                      .padding(.vertical, Spacing.xs)
                      .background(Palette.surfaceAlt, in: Capsule())
                      .padding(.top, Spacing.xs)
                  }
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xxl)
      }
    }
    .wcoachToasts()
  }
}
