import ChessCoachKit
import ChessKit
import SwiftUI

/// First-run flow: chess.com username → style → instinct quiz → placement → reconcile.
struct OnboardingView: View {
  @Environment(TrainingService.self) private var training
  @Environment(AnalysisService.self) private var analysis
  @State private var step: Step = .welcome
  @State private var username = "Zammy009"
  @State private var style: LearnerProfile.Style = .allRounder
  @State private var quizAnswers: [Bool] = []  // true = picked the sharp move
  @State private var placement = PlacementState()

  enum Step: Int, CaseIterable { case welcome, username, style, quiz, placement, result }

  var body: some View {
    ZStack {
      if step == .placement {
        ChessChrome.background.ignoresSafeArea()
      } else {
        BackgroundAtmosphere().ignoresSafeArea()
      }
      VStack(spacing: 0) {
        progress
        Group {
          switch step {
          case .welcome: welcome
          case .username: usernameStep
          case .style: styleStep
          case .quiz: quizStep
          case .placement: placementStep
          case .result: resultStep
          }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
      }
    }
    .preferredColorScheme(step == .placement ? .dark : .light)
    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: step)
  }

  private var progress: some View {
    HStack(spacing: 4) {
      ForEach(Step.allCases.dropFirst(), id: \.self) { s in
        Capsule().fill(s.rawValue <= step.rawValue ? Palette.primaryDeep : Palette.border).frame(height: 4)
      }
    }
    .padding(.horizontal, Spacing.xl)
    .padding(.top, Spacing.m)
    .opacity(step == .welcome ? 0 : 1)
  }

  // MARK: - Steps

  private var welcome: some View {
    VStack(alignment: .leading, spacing: Spacing.l) {
      Spacer()
      LogoMark()
        .frame(width: 72, height: 72)
      Text("Your chess coach").font(Typography.display).foregroundStyle(Palette.ink)
      Text("It reads your games, finds what's costing you points, and builds a 15-minute plan every day. Three minutes to set up.")
        .font(Typography.body).foregroundStyle(Palette.textSecondary)
      Spacer()
      PrimaryButton(title: "Let's go", action: { step = .username }, icon: "arrow.right")
        .accessibilityIdentifier("onboarding-start")
    }
    .padding(Spacing.xl)
  }

  private var usernameStep: some View {
    VStack(alignment: .leading, spacing: Spacing.l) {
      Eyebrow(text: "Step 1 · Your games")
      Text("Your chess.com username").font(Typography.title).foregroundStyle(Palette.ink)
      Text("We'll import your recent games in the background so the coach learns your habits.")
        .font(Typography.callout).foregroundStyle(Palette.textSecondary)
      TextField("Username", text: $username)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(Typography.titleSmall)
        .padding(Spacing.l)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: Spacing.cornerMedium))
        .overlay(RoundedRectangle(cornerRadius: Spacing.cornerMedium).stroke(Palette.border))
      Spacer()
      PrimaryButton(title: "Continue", action: {
        analysis.username = username.trimmingCharacters(in: .whitespaces)
        Task { await analysis.importFromChessCom() }
        step = .style
      }, icon: "arrow.right")
      Button("Skip") { step = .style }
        .font(Typography.callout).foregroundStyle(Palette.textSecondary).frame(maxWidth: .infinity)
    }
    .padding(Spacing.xl)
  }

  private var styleStep: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      Eyebrow(text: "Step 2 · Your style")
      Text("What kind of player do you want to become?").font(Typography.title).foregroundStyle(Palette.ink)
      Text("This shapes your openings, model games and how the coach talks. The basics come first either way.")
        .font(Typography.callout).foregroundStyle(Palette.textSecondary)
      ScrollView {
        VStack(spacing: Spacing.m) {
          ForEach(LearnerProfile.Style.allCases, id: \.self) { s in
            StyleCard(style: s, selected: style == s) { style = s }
              .accessibilityIdentifier("style-\(s.rawValue)")
          }
        }
      }
      PrimaryButton(title: "Continue", action: { step = .quiz }, icon: "arrow.right")
    }
    .padding(Spacing.xl)
  }

  private var quizStep: some View {
    let index = quizAnswers.count
    return VStack(alignment: .leading, spacing: Spacing.m) {
      Eyebrow(text: "Step 3 · Instinct · \(min(index + 1, InstinctQuiz.items.count)) of \(InstinctQuiz.items.count)")
      Text("Which move would you rather play?").font(Typography.title).foregroundStyle(Palette.ink)
      Text("Both are good. There's no wrong answer — we're learning your taste.")
        .font(Typography.callout).foregroundStyle(Palette.textSecondary)
      if index < InstinctQuiz.items.count {
        let item = InstinctQuiz.items[index]
        BoardView(
          position: Position(fen: item.fen) ?? .standard,
          annotations: {
            var a = AnnotationLayer()
            if let s = UCIMove(item.sharp) { a.arrows.append(Arrow(from: s.from, to: s.to, color: .red)) }
            if let q = UCIMove(item.quiet) { a.arrows.append(Arrow(from: q.from, to: q.to, color: .blue)) }
            return a
          }(),
          flipped: item.fen.contains(" b "),
          interactive: false)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerSmall))
        .id(index)
        HStack(spacing: Spacing.m) {
          QuizChoice(label: item.sharpSAN, detail: item.sharpNote, color: AnnotationColor.red.swiftUIColor) { quizAnswers.append(true) }
            .accessibilityIdentifier("quiz-sharp")
          QuizChoice(label: item.quietSAN, detail: item.quietNote, color: AnnotationColor.blue.swiftUIColor) { quizAnswers.append(false) }
            .accessibilityIdentifier("quiz-quiet")
        }
      }
    }
    .padding(Spacing.xl)
    .onChange(of: quizAnswers.count) { _, count in
      if count >= InstinctQuiz.items.count { step = .placement }
    }
  }

  private var placementStep: some View {
    VStack(spacing: 0) {
      Text("Step 4 · Placement · \(min(placement.done + 1, PlacementState.total)) of \(PlacementState.total)")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(ChessChrome.textSecondary)
        .padding(.top, Spacing.s)
      if let puzzle = placement.current {
        PuzzleView(puzzle: puzzle, rated: false) { outcome in
          placement.record(solved: outcome.solvedCleanly)
          placement.current = nil
          if placement.done >= PlacementState.total { step = .result }
        }
        .id(puzzle.id)
      } else {
        Spacer()
        ProgressView().tint(ChessChrome.textSecondary)
        Spacer()
      }
    }
    .task(id: placement.done) { loadPlacementPuzzle() }
  }

  private var resultStep: some View {
    let quiz = InstinctQuiz.score(quizAnswers)
    let mismatch = InstinctQuiz.mismatch(style: style, quizScore: quiz)
    return VStack(alignment: .leading, spacing: Spacing.l) {
      Eyebrow(text: "All set")
      Text("Here's where we start").font(Typography.title).foregroundStyle(Palette.ink)
      Card {
        let real = training.realRating
        Eyebrow(text: "Starting rating")
        Text("\(RatingAnchor.blend(placement: placement.rating, real: real))").font(Typography.weightLarge).foregroundStyle(Palette.ink)
        Text(real.map { "Your chess.com rating is \($0); \(placement.solved) of \(placement.done) placement puzzles adjusted it slightly." }
          ?? "Based on \(placement.done) placement puzzles (\(placement.solved) solved).")
          .font(Typography.caption).foregroundStyle(Palette.textSecondary)
      }
      Card {
        Eyebrow(text: "Your style")
        Text("\(style.title) — like \(style.model)").font(Typography.titleSmall).foregroundStyle(Palette.ink)
        Text(InstinctQuiz.describe(quiz)).font(Typography.callout).foregroundStyle(Palette.textSecondary).padding(.top, Spacing.xs)
        if let suggestion = mismatch {
          Text("Your instincts lean \(suggestion.title.lowercased()). Train as \(style.title) or switch?")
            .font(Typography.callout).foregroundStyle(Palette.accentDeep).padding(.top, Spacing.s)
          HStack {
            Chip(title: "Keep \(style.title)", isSelected: true) {}
            Chip(title: "Switch to \(suggestion.title)") { style = suggestion }
          }
          .padding(.top, Spacing.xs)
        }
      }
      Spacer()
      PrimaryButton(title: "Build my plan", action: finish, icon: "sparkles")
        .accessibilityIdentifier("onboarding-finish")
    }
    .padding(Spacing.xl)
  }

  // MARK: - Actions

  private func loadPlacementPuzzle() {
    guard placement.current == nil, placement.done < PlacementState.total else { return }
    let themes = ["mateIn1", "hangingPiece", "fork", "mateIn1", "backRankMate"]
    let theme = themes[placement.done % themes.count]
    guard let puzzle = (try? training.puzzles?.puzzles(theme: theme, around: placement.rating, excluding: placement.seen, limit: 1))??.first
    else {
      step = .result  // no bundle: skip placement
      return
    }
    placement.current = puzzle
    placement.seen.insert(puzzle.id)
  }

  private func finish() {
    training.completeOnboarding(
      LearnerProfile(
        username: username, style: style, quizScore: InstinctQuiz.score(quizAnswers), historyScore: nil,
        placementRating: placement.rating, onboardedAt: Date()))
  }
}

/// Staircase placement: start at 700, ±150 then shrinking steps.
struct PlacementState {
  static let total = 10
  var rating = 700
  var done = 0
  var solved = 0
  var current: Puzzle?
  var seen: Set<String> = []

  mutating func record(solved ok: Bool) {
    let step = max(50, 200 - done * 20)
    rating = max(400, min(2000, rating + (ok ? step : -step)))
    done += 1
    if ok { solved += 1 }
  }
}

/// Seven positions, each with a sharp and a quiet move (both sound), from real openings.
enum InstinctQuiz {
  struct Item {
    let fen: String
    let sharp: String
    let sharpSAN: String
    let sharpNote: String
    let quiet: String
    let quietSAN: String
    let quietNote: String
  }

  static let items: [Item] = [
    Item(fen: "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", sharp: "b2b4", sharpSAN: "b4",
         sharpNote: "Evans Gambit: a pawn for a fast attack", quiet: "d2d3", quietSAN: "d3", quietNote: "Solid build-up"),
    Item(fen: "r1bqkbnr/pppp1ppp/2n5/8/3pP3/5N2/PPP2PPP/RNBQKB1R w KQkq - 0 4", sharp: "c2c3", sharpSAN: "c3",
         sharpNote: "Göring Gambit: open lines, quick development", quiet: "f3d4", quietSAN: "Nxd4", quietNote: "Take the pawn back"),
    Item(fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", sharp: "f2f4", sharpSAN: "f4",
         sharpNote: "King's Gambit: romantic and risky", quiet: "g1f3", quietSAN: "Nf3", quietNote: "Develop and attack e5"),
    Item(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", sharp: "c7c5", sharpSAN: "c5",
         sharpNote: "Sicilian: fight for the win", quiet: "c7c6", quietSAN: "c6", quietNote: "Caro-Kann: rock solid"),
    Item(fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1", sharp: "f7f5", sharpSAN: "f5",
         sharpNote: "Dutch: unbalance from move one", quiet: "d7d5", quietSAN: "d5", quietNote: "Classical: claim the centre"),
    Item(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", sharp: "f3g5", sharpSAN: "Ng5",
         sharpNote: "Hit f7 right now", quiet: "d2d3", quietSAN: "d3", quietNote: "Calm Italian, castle first"),
    Item(fen: "rnbqkbnr/pppp1ppp/8/8/3pP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 3", sharp: "c2c3", sharpSAN: "c3",
         sharpNote: "Danish Gambit: bishops on fire", quiet: "d1d4", quietSAN: "Qxd4", quietNote: "Win the pawn back"),
  ]

  /// −1 (always quiet) … +1 (always sharp).
  static func score(_ answers: [Bool]) -> Double {
    guard !answers.isEmpty else { return 0 }
    return Double(answers.filter { $0 }.count * 2 - answers.count) / Double(answers.count)
  }

  static func describe(_ score: Double) -> String {
    switch score {
    case 0.4...: "Your instincts are sharp: you like initiative and open lines."
    case ..<(-0.4): "Your instincts are solid: you like safety and structure."
    default: "Your instincts are balanced between attack and safety."
    }
  }

  /// A suggested style when the quiz clearly disagrees with the pick.
  static func mismatch(style: LearnerProfile.Style, quizScore: Double) -> LearnerProfile.Style? {
    switch style {
    case .positional where quizScore >= 0.4: .attacker
    case .attacker where quizScore <= -0.4: .positional
    case .tactician where quizScore <= -0.6: .positional
    default: nil
    }
  }
}

private struct StyleCard: View {
  let style: LearnerProfile.Style
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.selection(); action() }) {
      HStack(spacing: Spacing.l) {
        Text(String(style.model.prefix(1)))
          .font(.system(size: 24, weight: .medium, design: .serif))
          .frame(width: 48, height: 48)
          .background(Circle().fill(selected ? Palette.primary : Palette.surfaceAlt))
          .foregroundStyle(selected ? Palette.textOnDark : Palette.primaryDeep)
        VStack(alignment: .leading, spacing: 2) {
          Text("\(style.title)").font(Typography.titleSmall).foregroundStyle(Palette.ink)
          Text("Like \(style.model) · \(style.tagline)").font(Typography.callout).foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.leading)
        }
        Spacer(minLength: 0)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? Palette.primaryDeep : Palette.textMuted)
      }
      .padding(Spacing.l)
      .background(Palette.paper)
      .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
        .stroke(selected ? Palette.primaryDeep : Palette.border, lineWidth: selected ? 1.5 : 0.75))
    }
    .buttonStyle(.plain)
  }
}

private struct QuizChoice: View {
  let label: String
  let detail: String
  let color: Color
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.light(); action() }) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        HStack(spacing: 6) {
          Circle().fill(color).frame(width: 10, height: 10)
          Text(label).font(Typography.titleSmall).foregroundStyle(Palette.ink)
        }
        Text(detail).font(Typography.caption).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.leading)
      }
      .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
      .padding(Spacing.m)
      .background(Palette.paper)
      .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous).stroke(Palette.border, lineWidth: 0.75))
    }
    .buttonStyle(.plain)
  }
}
