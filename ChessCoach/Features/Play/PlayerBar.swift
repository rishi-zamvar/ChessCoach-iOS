import ChessCoachKit
import ChessKit
import SwiftUI

/// Avatar, name, rating, captured material and clock — one per side.
struct PlayerBar: View {
  let name: String
  let rating: Int?
  let color: Piece.Color
  let captured: [Piece]
  let advantage: Int
  let clock: String?
  let clockActive: Bool
  let lowTime: Bool
  let thinking: Bool
  let pieceSet: PieceSetID

  var body: some View {
    HStack(spacing: Spacing.s) {
      avatar
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(name)
            .font(.system(.subheadline).weight(.semibold))
            .foregroundStyle(Palette.textPrimary)
          if let rating {
            Text("(" + String(rating) + ")")
              .font(.system(.callout))
              .foregroundStyle(Palette.textSecondary)
          }
          if thinking {
            ProgressView().controlSize(.mini).tint(Palette.textSecondary)
          }
        }
        CapturedRow(captured: captured, advantage: advantage, pieceSet: pieceSet)
      }
      Spacer(minLength: 0)
      if let clock {
        Text(clock)
          .font(.system(.title3, design: .monospaced).weight(.semibold))
          .foregroundStyle(clockForeground)
          .padding(.horizontal, Spacing.m)
          .frame(minWidth: 96, minHeight: 40, alignment: .trailing)
          .background(RoundedRectangle(cornerRadius: 4).fill(clockBackground))
          .accessibilityIdentifier("clock-\(color.rawValue)")
      }
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
  }

  private var clockForeground: Color {
    if lowTime && clockActive { return .white }
    return clockActive ? Palette.clockActiveText : Palette.clockIdleText
  }

  private var clockBackground: Color {
    if lowTime && clockActive { return Palette.danger }
    return clockActive ? Palette.clockActiveBG : Palette.clockIdleBG
  }

  private var avatar: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 4)
        .fill(Palette.surfaceRaised)
      if name == "You" {
        Image(systemName: "person.fill")
          .font(.system(.title3))
          .foregroundStyle(Palette.textSecondary)
      } else {
        Image(pieceSet.assetName(color: color, kind: .knight))
          .resizable()
          .padding(4)
      }
    }
    .frame(width: 40, height: 40)
  }
}

/// Small captured-piece icons grouped by kind, plus "+N" material lead.
private struct CapturedRow: View {
  let captured: [Piece]
  let advantage: Int
  let pieceSet: PieceSetID

  private static let order: [Piece.Kind] = [.pawn, .knight, .bishop, .rook, .queen]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Self.order, id: \.self) { kind in
        let group = captured.filter { $0.kind == kind }
        if !group.isEmpty {
          HStack(spacing: -9) {
            ForEach(Array(group.enumerated()), id: \.offset) { _, piece in
              Image(pieceSet.assetName(color: piece.color, kind: piece.kind))
                .resizable()
                .frame(width: 16, height: 16)
            }
          }
        }
      }
      if advantage > 0 {
        Text("+\(advantage)")
          .font(.system(.caption).weight(.semibold))
          .foregroundStyle(Palette.textSecondary)
      }
    }
    .frame(height: 16)
  }
}
