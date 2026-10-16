import ChessCoachKit
import ChessKit
import SwiftUI

/// Play tab: choose an opponent, color and time control, then start a game.
struct PlayHomeView: View {
  @Environment(AppEnvironment.self) private var env
  @State private var opponent: Opponent = .maia(rating: 1100)
  @State private var colorChoice: ColorChoice = .white
  @State private var timeControl: TimeControl = .untimed
  @State private var activeGame: GameController?
  @State private var showEngineMissing = false

  var body: some View {
    ZStack {
      BackgroundAtmosphere().ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.xl) {
          VStack(alignment: .leading, spacing: Spacing.s) {
            Eyebrow(text: "Play")
            Text("New game")
              .font(Typography.display)
              .foregroundStyle(Palette.ink)
          }

          SectionHeader(title: "Opponent")
          VStack(spacing: Spacing.m) {
            OpponentCard(
              title: "Coach bot",
              subtitle: env.ai.isAvailable
                ? "Plays at your level and sets up the patterns you're learning."
                : "Plays at your level, with a coach in your corner.",
              systemImage: "sparkles", selected: opponent == .teaching
            ) {
              opponent = .teaching
            } accessory: {
              EmptyView()
            }
            .accessibilityIdentifier("opponent-teaching")
            OpponentCard(
              title: "Maia 1100", subtitle: "Plays like a real 1100 — human mistakes and all.",
              systemImage: "person.fill", selected: opponent == .maia(rating: 1100)
            ) {
      opponent = .maia(rating: 1100)
    } accessory: {
      EmptyView()
    }
            .accessibilityIdentifier("opponent-maia")
            stockfishCard
          }

          SectionHeader(title: "Play as")
          HStack(spacing: Spacing.s) {
            ForEach(ColorChoice.allCases, id: \.self) { choice in
              Chip(title: choice.rawValue.capitalized, isSelected: colorChoice == choice) { colorChoice = choice }
            }
          }

          SectionHeader(title: "Time control")
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
              ForEach(TimeControl.presets, id: \.self) { tc in
                Chip(title: tc.label, isSelected: timeControl == tc) { timeControl = tc }
              }
            }
          }

        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.xl)
      }
      .safeAreaInset(edge: .bottom) {
        PrimaryButton(title: "Play", action: startGame, icon: "play.fill")
          .accessibilityIdentifier("play-start")
          .padding(.horizontal, Spacing.xl)
          .padding(.vertical, Spacing.s)
      }
    }
    .fullScreenCover(item: $activeGame) { game in
      GameScreen(game: game) { activeGame = nil }
    }
    .alert("Engines missing", isPresented: $showEngineMissing) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Run scripts/fetch-engine-assets.sh and rebuild to bundle Stockfish and Maia.")
    }
  }

  private var stockfishLevel: Int {
    if case .stockfish(let level) = opponent { return level }
    return 3
  }

  private var stockfishCard: some View {
    let isSelected: Bool = {
      if case .stockfish = opponent { return true }
      return false
    }()
    return OpponentCard(
      title: "Stockfish", subtitle: "Engine at a fixed level · ~\(BotLevel.level(stockfishLevel).displayRating)",
      systemImage: "cpu", selected: isSelected
    ) {
      opponent = .stockfish(level: stockfishLevel)
    } accessory: {
      if isSelected {
        HStack(spacing: Spacing.s) {
          StepperButton(direction: .minus) { opponent = .stockfish(level: max(1, stockfishLevel - 1)) }
          Text("Level \(stockfishLevel)")
            .font(Typography.bodyEmph)
            .foregroundStyle(Palette.ink)
            .frame(minWidth: 72)
          StepperButton(direction: .plus) { opponent = .stockfish(level: min(8, stockfishLevel + 1)) }
        }
      }
    }
    .accessibilityIdentifier("opponent-stockfish")
  }

  private func startGame() {
    let config = PlayConfig(opponent: opponent, userColor: colorChoice.resolve(), timeControl: timeControl)
    guard let game = env.makeGame(config) else {
      showEngineMissing = true
      return
    }
    activeGame = game
  }
}

private struct OpponentCard<Accessory: View>: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let selected: Bool
  let action: () -> Void
  @ViewBuilder var accessory: () -> Accessory

  var body: some View {
    Button(action: { Haptics.selection(); action() }) {
      HStack(alignment: .top, spacing: Spacing.l) {
        Image(systemName: systemImage)
          .font(.system(size: 20, weight: .medium))
          .frame(width: 44, height: 44)
          .background(Circle().fill(selected ? Palette.primary : Palette.surfaceAlt))
          .foregroundStyle(selected ? Palette.textOnDark : Palette.primaryDeep)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(title).font(Typography.titleSmall).foregroundStyle(Palette.ink)
          Text(subtitle).font(Typography.callout).foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.leading)
          accessory()
            .padding(.top, Spacing.xs)
        }
        Spacer(minLength: 0)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? Palette.primaryDeep : Palette.textMuted)
      }
      .padding(Spacing.l)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.paper)
      .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
          .stroke(selected ? Palette.primaryDeep : Palette.border, lineWidth: selected ? 1.5 : 0.75))
    }
    .buttonStyle(.plain)
  }
}

extension GameController: Identifiable {
  public nonisolated var id: UUID { gameID }
}
