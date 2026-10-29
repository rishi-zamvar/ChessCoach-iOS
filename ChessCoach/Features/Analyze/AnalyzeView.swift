import ChessCoachKit
import SwiftUI

/// Which games the Analyze list shows.
enum GameFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case chesscom = "chess.com"
  case local = "Played here"

  var id: String { rawValue }

  func apply(_ games: [GameRecord]) -> [GameRecord] {
    switch self {
    case .all: games
    case .chesscom: games.filter { $0.source == .chesscom }
    case .local: games.filter { $0.source == .local }
    }
  }
}

/// Saved and imported games, newest first. Tap one to open Game Review.
struct AnalyzeView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(AnalysisService.self) private var analysis
  @State private var games: [GameRecord] = []
  @State private var patterns: [MistakePattern] = []
  @State private var filter: GameFilter = .all
  @State private var reviewing: GameRecord?
  @State private var editingUsername = false
  @State private var usernameDraft = ""
  @State private var didAutoImport = false

  var body: some View {
    ZStack(alignment: .top) {
      BackgroundAtmosphere()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          Eyebrow(text: "Analyze")
          Text("Your games")
            .font(Typography.display)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, Spacing.s)

          importCard

          if !patterns.isEmpty { mistakesCard }

          HStack(spacing: Spacing.s) {
            ForEach(GameFilter.allCases) { f in
              Chip(title: f.rawValue, isSelected: filter == f) { filter = f }
            }
          }

          let shown = filter.apply(games)
          if shown.isEmpty {
            Card {
              EmptyState(
                title: "No games yet",
                message: "Play a game or import from chess.com and it will show up here for review.",
                systemImage: "checkerboard.rectangle")
            }
          } else {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, game in
              Button { reviewing = game } label: {
                GameRow(game: game, reviewed: analysis.isAnalyzed(game.id))
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("game-row-\(index)")
            }
          }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xxl)
      }

      if let progress = analysis.progress { ProgressBanner(progress: progress) }
    }
    .refreshable { await analysis.importFromChessCom() }
    .task(id: analysis.revision) { reload() }
    .task {
      guard !didAutoImport else { return }
      didAutoImport = true
      reload()
      if !games.contains(where: { $0.source == .chesscom }) { await analysis.importFromChessCom() }
    }
    .fullScreenCover(item: $reviewing) { ReviewScreen(game: $0) }
    .alert("chess.com username", isPresented: $editingUsername) {
      TextField("Username", text: $usernameDraft)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Save") {
        let name = usernameDraft.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { analysis.username = name }
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func reload() {
    games = (try? env.gameStore.recent(limit: 200)) ?? []
    patterns = analysis.recurringPatterns()
  }

  private var importCard: some View {
    Card {
      Eyebrow(text: "chess.com")
      Button {
        usernameDraft = analysis.username
        editingUsername = true
      } label: {
        HStack(spacing: Spacing.s) {
          Text(analysis.username.isEmpty ? "Add your chess.com username" : analysis.username)
            .font(Typography.titleSmall)
            .foregroundStyle(analysis.username.isEmpty ? Palette.primaryDeep : Palette.ink)
          Image(systemName: "pencil")
            .font(.system(.footnote).weight(.semibold))
            .foregroundStyle(Palette.textMuted)
        }
      }
      .buttonStyle(.plain)
      .padding(.vertical, Spacing.s)

      HStack(spacing: Spacing.s) {
        if analysis.importState == .running {
          ProgressView().controlSize(.small)
          Text("Checking chess.com…")
        } else {
          Image(systemName: "arrow.down")
          Text(analysis.lastImportAt.map { "Pull down to refresh · checked \($0.formatted(.relative(presentation: .named)))" }
            ?? "Pull down to fetch your games")
        }
      }
      .font(Typography.callout)
      .foregroundStyle(Palette.textSecondary)
      .accessibilityIdentifier("import-status")

      switch analysis.importState {
      case .finished(let n):
        Text(n == 0 ? "Up to date" : "\(n) new game\(n == 1 ? "" : "s")")
          .font(Typography.callout)
          .foregroundStyle(Palette.textSecondary)
          .padding(.top, Spacing.s)
      case .failed(let message):
        Text(message)
          .font(Typography.callout)
          .foregroundStyle(Palette.danger)
          .padding(.top, Spacing.s)
      case .idle, .running:
        EmptyView()
      }
    }
  }

  private var mistakesCard: some View {
    Card {
      Eyebrow(text: "Recurring mistakes")
      VStack(alignment: .leading, spacing: Spacing.s) {
        ForEach(patterns.prefix(4)) { p in
          Text("\(p.title) · \(p.count)× in \(p.games) game\(p.games == 1 ? "" : "s")")
            .font(Typography.bodyEmph)
            .foregroundStyle(Palette.ink)
        }
      }
      .padding(.top, Spacing.m)
      Text("From your analyzed games")
        .font(Typography.caption)
        .foregroundStyle(Palette.textMuted)
        .padding(.top, Spacing.m)
    }
  }
}

private struct ProgressBanner: View {
  let progress: AnalysisService.Progress

  var body: some View {
    HStack(spacing: Spacing.s) {
      ProgressView().controlSize(.small)
      Text(text)
        .font(Typography.callout)
        .foregroundStyle(Palette.ink)
    }
    .padding(.horizontal, Spacing.l)
    .padding(.vertical, Spacing.s)
    .background(Palette.paper, in: Capsule())
    .overlay(Capsule().stroke(Palette.border, lineWidth: 0.75))
    .padding(.top, Spacing.s)
  }

  private var text: String {
    var s = "Analyzing… \(progress.done)/\(progress.total)"
    if let eta = progress.etaSeconds {
      let left = max(0, eta * (1 - progress.fraction))
      s += " · ~\(Int(left.rounded()))s"
    }
    return s
  }
}

private struct GameRow: View {
  let game: GameRecord
  let reviewed: Bool

  private var ratings: String? {
    let mine = game.userColor == "white" ? game.whiteElo : game.blackElo
    let theirs = game.userColor == "white" ? game.blackElo : game.whiteElo
    guard let mine, let theirs else { return nil }
    return "You \(mine) vs \(game.opponentName) \(theirs)"
  }

  var body: some View {
    Card {
      HStack(spacing: Spacing.m) {
        OutcomeBadge(outcome: game.outcome)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text("vs \(game.opponentName)")
            .font(Typography.heading)
            .foregroundStyle(Palette.ink)
          Text("Played \(game.userColor) · \(game.terminationText) · \(game.timeControlText)")
            .font(Typography.callout)
            .foregroundStyle(Palette.textSecondary)
          if let ratings {
            Text(ratings)
              .font(Typography.caption)
              .foregroundStyle(Palette.textSecondary)
          }
          HStack(spacing: Spacing.s) {
            Text(game.endedAt.formatted(date: .abbreviated, time: .shortened))
            if let acc = game.chessComAccuracy {
              Text("· Accuracy \(acc.formatted(.number.precision(.fractionLength(1))))")
            }
          }
          .font(Typography.caption)
          .foregroundStyle(Palette.textMuted)
        }
        Spacer()
        if reviewed {
          Label("Reviewed", systemImage: "checkmark.circle.fill")
            .font(Typography.caption)
            .foregroundStyle(Palette.primaryDeep)
            .labelStyle(.titleAndIcon)
        } else {
          Text("Review")
            .font(Typography.caption)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(Palette.primaryDeep)
            .background(Palette.surfaceAlt, in: Capsule())
            .overlay(Capsule().stroke(Palette.border, lineWidth: 0.75))
        }
      }
    }
  }
}
