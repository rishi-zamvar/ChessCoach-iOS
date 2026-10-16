import ChessCoachKit
import ChessKit
import SwiftUI

/// chess.com-style promotion column dropped over the promotion square.
struct PromotionPicker: View {
  let square: Square
  let color: Piece.Color
  let pieceSet: PieceSetID
  let flipped: Bool
  let onPick: (Piece.Kind) -> Void
  let onCancel: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let geo = BoardGeometry(size: side, flipped: flipped)
      let sq = geo.squareSize
      let origin = geo.origin(of: square)
      // Column grows downward from the top edge, or upward from the bottom edge.
      let growsDown = geo.cell(of: square).row == 0
      ZStack(alignment: .topLeading) {
        Color.black.opacity(0.35)
          .onTapGesture(perform: onCancel)
        VStack(spacing: 0) {
          ForEach(growsDown ? kinds : kinds.reversed(), id: \.self) { kind in
            Button {
              onPick(kind)
            } label: {
              Image(pieceSet.assetName(color: color, kind: kind))
                .resizable()
                .padding(sq * 0.06)
                .frame(width: sq, height: sq)
                .background(Circle().fill(Color.white.opacity(0.92)).padding(sq * 0.04))
            }
            .accessibilityIdentifier("promote-\(kind.rawValue)")
          }
        }
        .background(Color(hex: 0xF5F5F5).opacity(0.0))
        .offset(x: origin.x, y: growsDown ? origin.y : origin.y - sq * 3)
      }
      .frame(width: side, height: side)
    }
    .aspectRatio(1, contentMode: .fit)
  }

  private var kinds: [Piece.Kind] { [.queen, .knight, .rook, .bishop] }
}
