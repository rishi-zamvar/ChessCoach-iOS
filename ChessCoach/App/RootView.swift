import ChessCoachKit
import SwiftUI
import UIKit

/// Root tab container. Each tab renders its own `BackgroundAtmosphere`; the tab bar is the
/// system's (Liquid Glass on iOS 26), never a custom background.
struct RootView: View {
    @State private var tab: Tab = .today
    @Environment(TrainingService.self) private var training
    @Environment(AppEnvironment.self) private var env
    @State private var showReports = false
    @State private var askConsent = false

    enum Tab: Hashable { case today, analyze, train, play }

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
        .tint(Palette.sage)
        .environment(\.selectTab, SelectTabAction { tab = $0 })
        .fullScreenCover(isPresented: Binding(get: { training.needsOnboarding }, set: { _ in })) {
            OnboardingView()
        }
        .onAppear(perform: skipOnboardingInUITests)
        .onShake { env.feedback.shake() }
        .onChange(of: env.feedback.prompt) { _, prompt in
            guard let prompt else { return }
            env.feedback.prompt = nil
            PromptBanner.show(prompt, center: env.feedback) { showReports = true }
        }
        .sheet(isPresented: $showReports) { NavigationStack { FeedbackListView() } }
        .sheet(isPresented: $askConsent) {
            TrainingProfileConsentSheet { choice in
                UserDefaults.standard.set(true, forKey: AnalyticsSetup.richAskedKey)
                AnalyticsSetup.setConsent(choice, profile: { training.analyticsProfile(env) }, userID: { AnalyticsSetup.userID })
                env.telemetry.event("onboarding.consent", metadata: ["value": .string(choice.rawValue)])
                askConsent = false
            }
        }
        .onChange(of: training.needsOnboarding) { _, needs in
            if !needs, AnalyticsSetup.shouldAskRich { askConsent = true }
        }
        .task {
            await env.feedback.flush()
            await env.feedback.refreshStatuses()
        }
    }

    /// UI tests start from a fresh in-memory store; skip onboarding unless a test asks for it.
    private func skipOnboardingInUITests() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting") else { return }
        // UI tests drive instant-mode puzzles unless a test opts into Coach mode.
        UserDefaults.standard.set((args.contains("-coachMode") ? PuzzleMode.coach : .instant).rawValue, forKey: PuzzleMode.key)
        guard !args.contains("-onboarding"), training.needsOnboarding else { return }
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
