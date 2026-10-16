import SwiftUI

@main
struct ChessCoachApp: App {
  @State private var env = AppEnvironment(inMemory: ProcessInfo.processInfo.arguments.contains("-uiTesting"))

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(env)
        .preferredColorScheme(.light)
    }
  }
}
