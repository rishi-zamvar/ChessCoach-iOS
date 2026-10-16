import ChessCoachKit
import ChessKit
import SwiftUI

/// The one chess board used on every screen.
///
/// Layers (back to front): squares + tints + coordinates (Canvas), move targets,
/// pieces (identity-stable so moves slide), annotation arrows/circles, dragged piece.
/// Gestures: tap-tap, drag-drop, and drag from a non-movable square to draw an arrow.
struct BoardView: View {
  var position: Position
  var highlights: BoardHighlights = .init()
  var annotations: AnnotationLayer = .init()
  var theme: BoardTheme = .default
  var pieceSet: PieceSetID = .default
  var flipped: Bool = false
  var showCoordinates: Bool = true
  var interactive: Bool = true
  var onTap: (Square) -> Void = { _ in }
  /// Return true if the piece may be dragged.
  var onDragBegan: (Square) -> Bool = { _ in false }
  var onDragEnded: (Square?) -> Void = { _ in }
  var onDragCancelled: () -> Void = {}
  var onArrow: (Square, Square) -> Void = { _, _ in }
  /// Small round badge at a square's top-right corner (move classification).
  var badge: SquareBadge? = nil

  @State private var identified: [IdentifiedPiece] = []
  @State private var nextID = 0
  @State private var gesture = GestureState()
  /// True while a finger is down; resets on its own when the system cancels the gesture.
  @SwiftUI.GestureState private var touching = false

  struct GestureState {
    var start: Square?
    var mode: Mode = .idle
    var location: CGPoint = .zero
    enum Mode { case idle, pending, dragPiece, drawArrow }
  }

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let geo = BoardGeometry(size: side, flipped: flipped)
      ZStack(alignment: .topLeading) {
        squaresLayer(geo)
        targetsLayer(geo)
        piecesLayer(geo)
        annotationLayer(geo)
        badgeLayer(geo)
        draggedPieceLayer(geo)
      }
      .frame(width: side, height: side)
      .contentShape(Rectangle())
      .gesture(interactive ? boardGesture(geo) : nil)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Chess board")
      .accessibilityIdentifier("board")
    }
    .aspectRatio(1, contentMode: .fit)
    .onAppear { reconcile() }
    .onChange(of: position.fen) { _, _ in
      withAnimation(.easeOut(duration: 0.15)) { reconcile() }
    }
    .onChange(of: interactive) { _, isInteractive in
      if !isInteractive { resetGesture() }
    }
    .onChange(of: touching) { _, isTouching in
      // onEnded runs first on a normal lift; anything still active here was cancelled.
      guard !isTouching else { return }
      DispatchQueue.main.async { if gesture.mode != .idle { resetGesture() } }
    }
  }

  // MARK: - Layers

  private func squaresLayer(_ geo: BoardGeometry) -> some View {
    Canvas { context, _ in
      let sq = geo.squareSize
      for square in Square.allCases {
        let rect = CGRect(origin: geo.origin(of: square), size: CGSize(width: sq, height: sq))
        let light = BoardGeometry.isLightSquare(square)
        context.fill(Path(rect), with: .color(Color(hex: light ? theme.light : theme.dark)))
        if highlights.lastMove.contains(square) {
          context.fill(Path(rect), with: .color(Color(hex: theme.lastMove, alpha: theme.lastMoveAlpha)))
        }
        if highlights.selected == square {
          context.fill(Path(rect), with: .color(Color(hex: theme.selected, alpha: 0.5)))
        }
        if highlights.premove.contains(square) {
          context.fill(Path(rect), with: .color(Color(hex: theme.premove, alpha: 0.6)))
        }
        if highlights.check == square {
          let gradient = Gradient(colors: [Color(hex: 0xFF0000, alpha: 0.9), Color(hex: 0xE70000, alpha: 0.45), .clear])
          context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(gradient, center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: sq * 0.6))
        }
        if showCoordinates {
          drawCoordinates(context: context, square: square, rect: rect, light: light, geo: geo)
        }
      }
    }
  }

  private func drawCoordinates(context: GraphicsContext, square: Square, rect: CGRect, light: Bool, geo: BoardGeometry) {
    let cell = geo.cell(of: square)
    let color = Color(hex: light ? theme.dark : theme.light)
    let font = Font.system(size: geo.squareSize * 0.2, weight: .semibold, design: .rounded)
    if cell.column == 0 {
      context.draw(
        Text("\(square.rank.value)").font(font).foregroundStyle(color),
        at: CGPoint(x: rect.minX + geo.squareSize * 0.1, y: rect.minY + geo.squareSize * 0.14), anchor: .topLeading)
    }
    if cell.row == 7 {
      context.draw(
        Text(square.file.rawValue).font(font).foregroundStyle(color),
        at: CGPoint(x: rect.maxX - geo.squareSize * 0.06, y: rect.maxY - geo.squareSize * 0.02), anchor: .bottomTrailing)
    }
  }

  private func targetsLayer(_ geo: BoardGeometry) -> some View {
    Canvas { context, _ in
      let sq = geo.squareSize
      let ink = Color.black.opacity(0.16)
      for square in highlights.targets {
        let c = geo.center(of: square)
        if position.piece(at: square) != nil {
          let r = sq * 0.46
          context.stroke(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(ink),
            lineWidth: sq * 0.08)
        } else {
          let r = sq * 0.16
          context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(ink))
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func piecesLayer(_ geo: BoardGeometry) -> some View {
    ForEach(identified) { item in
      let hidden = gesture.mode == .dragPiece && gesture.start == item.piece.square
      Image(pieceSet.assetName(color: item.piece.color, kind: item.piece.kind))
        .resizable()
        .interpolation(.high)
        .frame(width: geo.squareSize, height: geo.squareSize)
        .position(geo.center(of: item.piece.square))
        .opacity(hidden ? 0.35 : 1)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
    .allowsHitTesting(false)
  }

  private func annotationLayer(_ geo: BoardGeometry) -> some View {
    Canvas { context, _ in
      let sq = geo.squareSize
      for (square, color) in annotations.circles {
        strokeCircle(context: context, square: square, color: color, geo: geo)
      }
      for square in annotations.userCircles {
        strokeCircle(context: context, square: square, color: .yellow, geo: geo)
      }
      for arrow in annotations.arrows + annotations.userArrows {
        let path = ArrowPath.make(from: geo.center(of: arrow.from), to: geo.center(of: arrow.to), squareSize: sq, knightLike: ArrowPath.isKnightMove(arrow.from, arrow.to))
        context.fill(path, with: .color(arrow.color.swiftUIColor.opacity(0.8)))
      }
      if gesture.mode == .drawArrow, let start = gesture.start {
        let end = geo.square(at: gesture.location) ?? start
        if end != start {
          let path = ArrowPath.make(from: geo.center(of: start), to: geo.center(of: end), squareSize: sq, knightLike: ArrowPath.isKnightMove(start, end))
          context.fill(path, with: .color(AnnotationColor.yellow.swiftUIColor.opacity(0.6)))
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func strokeCircle(context: GraphicsContext, square: Square, color: AnnotationColor, geo: BoardGeometry) {
    let c = geo.center(of: square)
    let r = geo.squareSize * 0.44
    context.stroke(
      Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
      with: .color(color.swiftUIColor.opacity(0.85)), lineWidth: geo.squareSize * 0.07)
  }

  @ViewBuilder
  private func badgeLayer(_ geo: BoardGeometry) -> some View {
    if let badge {
      let origin = geo.origin(of: badge.square)
      let size = geo.squareSize * 0.42
      Text(badge.text)
        .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
        .minimumScaleFactor(0.5)
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(badge.color))
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .position(x: origin.x + geo.squareSize - size * 0.25, y: origin.y + size * 0.25)
        .allowsHitTesting(false)
        .transition(.scale.combined(with: .opacity))
    }
  }

  @ViewBuilder
  private func draggedPieceLayer(_ geo: BoardGeometry) -> some View {
    if gesture.mode == .dragPiece, let start = gesture.start, let piece = position.piece(at: start) {
      Image(pieceSet.assetName(color: piece.color, kind: piece.kind))
        .resizable()
        .frame(width: geo.squareSize * 1.15, height: geo.squareSize * 1.15)
        // Lift the piece above the finger so it stays visible.
        .position(x: gesture.location.x, y: gesture.location.y - geo.squareSize * 0.25)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
        .allowsHitTesting(false)
    }
  }

  // MARK: - Gestures

  private func boardGesture(_ geo: BoardGeometry) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .updating($touching) { _, state, _ in state = true }
      .onChanged { value in
        if gesture.mode == .idle {
          gesture.start = geo.square(at: value.startLocation)
          gesture.mode = .pending
        }
        gesture.location = value.location
        let moved = hypot(value.translation.width, value.translation.height) > geo.squareSize * 0.15
        if gesture.mode == .pending, moved, let start = gesture.start {
          gesture.mode = onDragBegan(start) ? .dragPiece : .drawArrow
        }
      }
      .onEnded { value in
        let endSquare = geo.square(at: value.location)
        switch gesture.mode {
        case .pending:
          if let start = gesture.start { onTap(start) }
        case .dragPiece:
          if let endSquare, endSquare != gesture.start {
            onDragEnded(endSquare)
          } else {
            onDragCancelled()
          }
        case .drawArrow:
          if let start = gesture.start, let endSquare { onArrow(start, endSquare) }
        case .idle:
          break
        }
        gesture = GestureState()
      }
  }

  private func resetGesture() {
    if gesture.mode == .dragPiece { onDragCancelled() }
    gesture = GestureState()
  }

  private func reconcile() {
    var id = nextID
    identified = PieceIdentity.reconcile(previous: identified, next: position.pieces, nextID: &id)
    nextID = id
  }
}

struct SquareBadge: Equatable {
  var square: Square
  var text: String
  var color: Color
}

extension AnnotationColor {
  var swiftUIColor: Color {
    switch self {
    case .green: Color(hex: 0x15781B)
    case .red: Color(hex: 0x882020)
    case .blue: Color(hex: 0x003088)
    case .yellow: Color(hex: 0xE68F00)
    }
  }
}

/// Arrow outlines (straight, or L-shaped for knight moves).
enum ArrowPath {
  static func isKnightMove(_ a: Square, _ b: Square) -> Bool {
    let df = abs(a.file.number - b.file.number)
    let dr = abs(a.rank.value - b.rank.value)
    return (df == 1 && dr == 2) || (df == 2 && dr == 1)
  }

  static func make(from: CGPoint, to: CGPoint, squareSize sq: CGFloat, knightLike: Bool) -> Path {
    let shaft = sq * 0.18
    let headLength = sq * 0.42
    let headWidth = sq * 0.5
    var path = Path()
    var points = [from]
    if knightLike {
      // Long leg first, then the short leg into the target.
      let dx = to.x - from.x
      let dy = to.y - from.y
      points.append(abs(dx) > abs(dy) ? CGPoint(x: to.x, y: from.y) : CGPoint(x: from.x, y: to.y))
    }
    points.append(to)

    for i in 0..<(points.count - 1) {
      let a = points[i]
      let b = points[i + 1]
      let isLast = i == points.count - 2
      let angle = atan2(b.y - a.y, b.x - a.x)
      let length = hypot(b.x - a.x, b.y - a.y)
      let start = i == 0 ? sq * 0.15 : -shaft / 2
      let end = isLast ? length - headLength : length + shaft / 2
      var segment = Path()
      segment.addRect(CGRect(x: start, y: -shaft / 2, width: max(0, end - start), height: shaft))
      if isLast {
        segment.move(to: CGPoint(x: end, y: -headWidth / 2))
        segment.addLine(to: CGPoint(x: length, y: 0))
        segment.addLine(to: CGPoint(x: end, y: headWidth / 2))
        segment.closeSubpath()
      }
      let transform = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: angle)
      path.addPath(segment, transform: transform)
    }
    return path
  }
}

#Preview {
  BoardView(
    position: Position(fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4")!,
    highlights: BoardHighlights(lastMove: [Square("d1"), Square("h5")], targets: [Square("f7")]),
    annotations: {
      var a = AnnotationLayer()
      a.arrows = [Arrow(from: Square("h5"), to: Square("f7"), color: .green), Arrow(from: Square("g1"), to: Square("f3"), color: .blue)]
      return a
    }()
  )
  .padding()
}
