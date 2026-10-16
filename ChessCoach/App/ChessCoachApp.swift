import SwiftUI

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
        .preferredColorScheme(.light)
    }
  }
}
