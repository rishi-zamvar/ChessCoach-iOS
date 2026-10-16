import SwiftUI

@main
struct ChessCoachApp: App {
  @State private var env: AppEnvironment
  @State private var analysis: AnalysisService

  init() {
    let env = AppEnvironment(inMemory: ProcessInfo.processInfo.arguments.contains("-uiTesting"))
    _env = State(initialValue: env)
    _analysis = State(initialValue: AnalysisService(env: env))
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(env)
        .environment(analysis)
        .preferredColorScheme(.light)
    }
  }
}
