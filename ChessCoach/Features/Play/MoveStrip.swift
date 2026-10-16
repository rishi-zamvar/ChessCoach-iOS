import ChessCoachKit
import SwiftUI

/// Horizontal SAN move list that keeps the current move in view (chess.com style).
struct MoveStrip: View {
  let history: [PlayedMove]
  let currentPly: Int
  var onSelect: (Int) -> Void

  var body: some View {
    ScrollViewReader { reader in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(Array(history.enumerated()), id: \.offset) { index, played in
            let ply = index + 1
            if index.isMultiple(of: 2) {
              Text("\(index / 2 + 1).")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(ChessChrome.textSecondary.opacity(0.7))
                .padding(.leading, index == 0 ? 0 : 6)
            }
            Button { onSelect(ply) } label: {
              Text(played.san)
                .font(.system(size: 14, weight: ply == currentPly ? .bold : .medium, design: .rounded))
                .foregroundStyle(ply == currentPly ? ChessChrome.textPrimary : ChessChrome.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                  RoundedRectangle(cornerRadius: 4)
                    .fill(ply == currentPly ? Color.white.opacity(0.18) : .clear))
            }
            .buttonStyle(.plain)
            .id(ply)
          }
          if history.isEmpty {
            Text("Make your move")
              .font(.system(size: 14, weight: .medium, design: .rounded))
              .foregroundStyle(ChessChrome.textSecondary.opacity(0.7))
          }
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: 36)
      }
      .accessibilityIdentifier("move-strip")
      .onChange(of: currentPly) { _, ply in
        withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(ply, anchor: .center) }
      }
    }
    .background(ChessChrome.bar.opacity(0.6))
  }
}
