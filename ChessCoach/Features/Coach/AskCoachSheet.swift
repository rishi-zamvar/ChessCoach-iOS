import ChessCoachKit
import ChessKit
import SwiftUI

/// "Ask the coach" about the position on screen. Answers come from Claude using the
/// phone's board tools; any arrows it draws are handed back to the board.
struct AskCoachSheet: View {
  let fen: String
  let history: [String]
  var suggestions: [String] = ["What's the plan here?", "What does their last move threaten?", "What should I look out for?"]
  let onArrows: ([Arrow]) -> Void

  @Environment(AppEnvironment.self) private var env
  @Environment(TrainingService.self) private var training
  @Environment(\.dismiss) private var dismiss
  @Environment(AnalysisService.self) private var analysis
  @State private var question = ""
  @State private var exchanges: [(q: String, a: String, grounded: Bool)] = []
  @State private var thinking = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: Spacing.m) {
        ConnectionBanner(isOnline: env.connectivity.isOnline, message: "Offline. The coach answers when you're back online.")
        if !env.ai.isAvailable {
          EmptyState(
            title: "Coach AI is off",
            message: "Add your own AI key in Settings → Coach AI to ask the coach. Everything else works without one.",
            systemImage: "sparkles")
          Spacer()
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
              ForEach(Array(exchanges.enumerated()), id: \.offset) { _, e in
                Text(e.q).font(Typography.bodyEmph).foregroundStyle(Palette.ink)
                  .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                  Text(e.a).font(Typography.body).foregroundStyle(Palette.ink)
                  if !e.grounded {
                    Label("Unverified — check the board", systemImage: "exclamationmark.triangle")
                      .font(Typography.caption).foregroundStyle(Palette.accentDeep)
                  }
                }
                .padding(Spacing.m)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: Spacing.cornerMedium))
                .accessibilityIdentifier("coach-answer")
              }
              if thinking { ProgressView("Coach is thinking…").padding() }
              if let error { Text(error).font(Typography.caption).foregroundStyle(Palette.danger) }
            }
            .padding(Spacing.l)
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
              ForEach(suggestions, id: \.self) { s in Chip(title: s) { send(s) } }
            }
            .padding(.horizontal, Spacing.l)
          }
          HStack {
            TextField("Ask about this position…", text: $question, axis: .vertical)
              .lineLimit(1...3)
              .padding(Spacing.m)
              .background(Palette.paper, in: RoundedRectangle(cornerRadius: Spacing.cornerMedium))
              .accessibilityIdentifier("coach-question")
            Button { send(question) } label: {
              Image(systemName: "arrow.up.circle.fill").font(Typography.symbol(32)).foregroundStyle(Palette.primaryDeep)
            }
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
          }
          .padding(.horizontal, Spacing.l)
          .padding(.bottom, Spacing.m)
        }
      }
      .background(Palette.canvas.ignoresSafeArea())
      .navigationTitle("Ask the coach")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .onAppear { analysis.beginForegroundEngineUse() }
    .onDisappear { analysis.endForegroundEngineUse() }
  }

  private func send(_ text: String) {
    let q = text.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty, !thinking else { return }
    question = ""
    thinking = true
    error = nil
    let coach = AskCoach(client: env.ai, tools: CoachTools(host: env.engineHost, profile: env.learnerBrief))
    Task {
      do {
        let answer = try await coach.ask(q, fen: fen, history: history)
        exchanges.append((q, answer.text, answer.grounded))
        if !answer.arrows.isEmpty { onArrows(answer.arrows) }
      } catch AIError.budgetExceeded {
        error = "This month's AI budget is used up."
      } catch {
        self.error = "The coach couldn't answer right now."
      }
      thinking = false
    }
  }
}
