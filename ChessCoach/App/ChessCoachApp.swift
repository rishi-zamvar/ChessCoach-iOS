import SwiftUI
import UIKit

@main
struct ChessCoachApp: App {
  @State private var env: AppEnvironment
  @State private var analysis: AnalysisService
  @State private var training: TrainingService

  init() {
    let env = AppEnvironment(inMemory: ProcessInfo.processInfo.arguments.contains("-uiTesting"))
    _env = State(initialValue: env)
    _analysis = State(initialValue: AnalysisService(env: env))
    _training = State(initialValue: TrainingService(env: env))
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(env)
        .environment(analysis)
        .environment(training)
        .task {
          analysis.onImported = { training.anchorToRealRating() }
          training.anchorToRealRating()
          await env.server.refresh()
          analysis.startBackgroundAnalysis()
          await analysis.importIfStale()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
          Task {
            await env.server.refresh()
            await analysis.importIfStale()
          }
        }
    }
  }
}
