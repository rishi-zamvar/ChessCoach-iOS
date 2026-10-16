import ChessCoachKit
import SwiftUI
import UIKit

/// Root tab container. Each tab renders its own `BackgroundAtmosphere` so it
/// draws under the tab bar correctly.
struct RootView: View {
    @State private var tab: Tab = .today
    @Environment(TrainingService.self) private var training

    enum Tab: Hashable { case today, analyze, train, play }

    init() {
        // Paper tab bar — opaque cream so atmosphere doesn't leak through.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Palette.paper)
        appearance.shadowColor = UIColor(Palette.border)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)
            AnalyzeView()
                .tabItem { Label("Analyze", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.analyze)
            TrainView()
                .tabItem { Label("Train", systemImage: "graduationcap") }
                .tag(Tab.train)
            PlayHomeView()
                .tabItem { Label("Play", systemImage: "play.circle") }
                .tag(Tab.play)
        }
        .tint(Palette.primaryDeep)
        .fullScreenCover(isPresented: .constant(training.needsOnboarding)) {
            OnboardingView()
        }
        .onAppear(perform: skipOnboardingInUITests)
    }

    /// UI tests start from a fresh in-memory store; skip onboarding unless a test asks for it.
    private func skipOnboardingInUITests() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting"), !args.contains("-onboarding"), training.needsOnboarding else { return }
        training.completeOnboarding(
            LearnerProfile(username: "Zammy009", style: .allRounder, quizScore: 0, historyScore: nil, placementRating: 700, onboardedAt: Date()))
    }
}

/// Editorial placeholder screen: atmosphere, eyebrow, display-serif title.
struct PlaceholderScreen: View {
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ZStack {
            BackgroundAtmosphere().ignoresSafeArea()
            VStack(alignment: .leading, spacing: Spacing.s) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(Typography.display)
                    .foregroundStyle(Palette.ink)
                Spacer()
                EmptyState(title: "Coming soon", message: message, systemImage: systemImage)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xxl)
        }
    }
}

#Preview { RootView() }
