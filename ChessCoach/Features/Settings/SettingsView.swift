import AuthenticationServices
import ChessCoachKit
import SwiftUI

/// Settings: profile (retake onboarding), chess.com username, board look, sound, AI provider.
struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(TrainingService.self) private var training
  @Environment(AnalysisService.self) private var analysis
  @Environment(AppEnvironment.self) private var env
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue
  @AppStorage(BoardSettings.coordinatesKey) private var showCoordinates = true
  @AppStorage(BoardSettings.soundKey) private var soundOn = true
  @AppStorage(BoardSettings.paceKey) private var paceRaw = ReplyPace.normal.rawValue
  @AppStorage(BoardSettings.coachModeKey) private var coachModeRaw = CoachMode.voice.rawValue
  @AppStorage(Haptics.key) private var hapticsOn = true
  @AppStorage(PuzzleMode.key) private var puzzleModeRaw = PuzzleMode.current.rawValue
  @State private var username = ""
  @State private var appleUserID = AppleAccount.userID
  @Environment(\.colorScheme) private var colorScheme
  @State private var confirmRetake = false
  /// Asks the presenter to reset the profile once this sheet is gone.
  var onRetake: () -> Void = {}

  var body: some View {
    NavigationStack {
      Form {
        Section("You") {
          if let p = training.profile {
            LabeledContent("Style", value: "\(p.style.title) · like \(p.style.model)")
            LabeledContent("Puzzle rating", value: "\(training.globalRating)")
          }
          Button("Retake onboarding") { confirmRetake = true }
            .accessibilityIdentifier("settings-retake")
        }
        Section {
          TextField("chess.com username", text: $username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { analysis.username = username.trimmingCharacters(in: .whitespaces) }
            .accessibilityIdentifier("settings-username")
          if appleUserID == nil {
            SignInWithAppleButton(.signIn) { $0.requestedScopes = [] } onCompletion: { result in
              if case .success(let auth) = result, let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                AppleAccount.userID = credential.user
                appleUserID = credential.user
              }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 44)
            .accessibilityIdentifier("settings-apple")
          } else {
            LabeledContent("Apple ID", value: "Signed in")
            Button("Sign out of Apple", role: .destructive) {
              AppleAccount.userID = nil
              appleUserID = nil
            }
          }
        } header: {
          Text("Account")
        } footer: {
          Text("Your chess.com username is your account. Games, ratings and progress stay on this phone.")
        }
        Section("Board") {
          Picker("Theme", selection: $themeID) {
            ForEach(BoardTheme.all) { Text($0.name).tag($0.id) }
          }
          Picker("Pieces", selection: $pieceSetRaw) {
            ForEach(PieceSetID.allCases) { set in
              HStack {
                Image(set.assetName(color: .white, kind: .knight)).resizable().frame(width: 22, height: 22)
                Text(set.displayName)
              }
              .tag(set.rawValue)
            }
          }
          Toggle("Coordinates", isOn: $showCoordinates)
          Toggle("Move sounds", isOn: $soundOn)
          Picker("Opponent replies", selection: $paceRaw) {
            ForEach(ReplyPace.allCases) { Text($0.title).tag($0.rawValue) }
          }
          Picker("Coach during games", selection: $coachModeRaw) {
            ForEach(CoachMode.allCases) { Text($0.title).tag($0.rawValue) }
          }
          if coachModeRaw == CoachMode.voice.rawValue {
            LabeledContent("Coach voice", value: CoachSpeaker.shared.voiceName)
            Button("Hear the coach") { CoachSpeaker.shared.say(CoachVoice.sample) }
          }
        }
        Section {
          Picker("Puzzle feedback", selection: $puzzleModeRaw) {
            ForEach(PuzzleMode.allCases) { Text($0.title).tag($0.rawValue) }
          }
          .accessibilityIdentifier("settings-puzzle-mode")
          Toggle("Haptics", isOn: $hapticsOn)
        } header: {
          Text("Puzzles & feel")
        } footer: {
          Text("Coach: play every puzzle out, then find your own mistake. Instant: right or wrong straight away. Quick warm-up and Puzzle Rush are always instant.")
        }
        AIProviderSection()
        PrivacySection()
        Section {
          Text("Knightlight \(FeedbackCenter.version) (\(FeedbackCenter.build)) · engines: Stockfish 17, Maia-1100 (Lc0) · puzzles & openings: Lichess (CC0)")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.surfaceBase.ignoresSafeArea())
      .tint(Palette.sage)
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { commit(); dismiss() } } }
      .onAppear { username = analysis.username }
      .confirmationDialog("Retake onboarding?", isPresented: $confirmRetake, titleVisibility: .visible) {
        Button("Retake") {
          commit()
          onRetake()
          dismiss()
        }
      } message: {
        Text("You'll pick your style and redo placement, which resets your overall puzzle rating. Games, reviews and skill ratings stay.")
      }
    }
  }

  private func commit() {
    let trimmed = username.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty { analysis.username = trimmed }
  }
}

/// Feedback and what the app shares (spec W7, W8).
private struct PrivacySection: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(TrainingService.self) private var training
  @AppStorage(FeedbackCenter.shakeKey) private var shake = FeedbackCenter.isTestFlight
  @AppStorage(AnalyticsSetup.consentKey) private var consentRaw = AnalyticsConsent.basic.rawValue
  @State private var confirmDelete = false
  @State private var deleteResult: String?

  var body: some View {
    Section {
      NavigationLink("Your feedback") { FeedbackListView() }
        .accessibilityIdentifier("settings-feedback")
      Toggle("Shake to send feedback", isOn: $shake)
      Toggle("Share anonymous usage", isOn: Binding(
        get: { consentRaw != AnalyticsConsent.off.rawValue },
        set: { set($0 ? .basic : .off) }))
        .accessibilityIdentifier("settings-analytics")
      Toggle("Share my training profile", isOn: Binding(
        get: { consentRaw == AnalyticsConsent.rich.rawValue },
        set: { set($0 ? .rich : .basic) }))
        .accessibilityIdentifier("settings-analytics-rich")
      Button("Delete my data", role: .destructive) { confirmDelete = true }
        .accessibilityIdentifier("settings-delete-data")
      if let deleteResult { Text(deleteResult).font(Typography.caption).foregroundStyle(Palette.textSecondary) }
      Link("Privacy policy", destination: AnalyticsSetup.privacyURL)
    } header: {
      Text("Privacy & feedback")
    } footer: {
      Text("Anonymous usage is which screens and features get used, with no name, games or text attached. Your training profile adds your chess.com name, ratings and puzzle results so we can coach you better; it's off unless you turn it on. Shake is ignored while you're playing.")
    }
    .confirmationDialog("Delete your data?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete", role: .destructive) {
        Task {
          let ok = await env.feedback.deleteMyData()
          consentRaw = AnalyticsSetup.consent.rawValue
          deleteResult = ok
            ? "Deleted: your feedback is gone and your usage profile is queued for deletion."
            : "Couldn't reach the server. Try again when you're online."
        }
      }
    } message: {
      Text("This removes the feedback and screenshots you've sent and deletes your usage profile. Games and progress on this phone stay.")
    }
  }

  private func set(_ value: AnalyticsConsent) {
    AnalyticsSetup.setConsent(value, profile: { training.analyticsProfile(env) }, userID: { AnalyticsSetup.userID })
    consentRaw = value.rawValue
    UserDefaults.standard.set(true, forKey: AnalyticsSetup.richAskedKey)
    env.telemetry.event("settings.change", metadata: ["key": .string("analytics"), "value": .string(value.rawValue)])
  }
}

/// Asked once after onboarding (when analytics is configured): opt in to the training profile.
struct TrainingProfileConsentSheet: View {
  let onChoice: (AnalyticsConsent) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.l) {
      Eyebrow(text: "One question")
      Text("Help us coach you better?").font(Typography.title).foregroundStyle(Palette.textPrimary)
      Text("Share your training profile: your chess.com name, ratings, playing style and how each puzzle went, plus screen recordings with every text field hidden. We use it to see where you get stuck and make the coaching sharper.")
        .font(Typography.body).foregroundStyle(Palette.textSecondary)
      Text("No ads, no selling, no tracking across other apps. Change your mind any time in Settings.")
        .font(Typography.callout).foregroundStyle(Palette.textTertiary)
      Spacer()
      PrimaryButton(title: "Share my training profile", action: { onChoice(.rich) })
        .accessibilityIdentifier("consent-rich")
      SecondaryButton(title: "Not now") { onChoice(.basic) }
        .accessibilityIdentifier("consent-basic")
      Link("Read the privacy policy", destination: AnalyticsSetup.privacyURL)
        .font(Typography.callout).frame(maxWidth: .infinity)
    }
    .padding(Spacing.xl)
    .background(Palette.surfaceBase.ignoresSafeArea())
    .interactiveDismissDisabled()
  }
}

/// Which LLM coaches you, with your own key. On the owner's tailnet the home PC fills Claude's key in.
private struct AIProviderSection: View {
  @Environment(AppEnvironment.self) private var env
  @State private var key = ""
  @State private var fast = ""
  @State private var smart = ""
  @State private var baseURL = ""

  var body: some View {
    let ai = env.aiSettings
    let provider = ai.provider
    Section {
      Picker("Provider", selection: Binding(get: { ai.provider }, set: { ai.provider = $0 })) {
        ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
      }
      .accessibilityIdentifier("ai-provider")
      SecureField(provider.needsKey ? "API key" : "API key (optional)", text: $key)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit { ai.setKey(key, for: provider) }
        .accessibilityIdentifier("ai-key")
      if provider == .custom {
        TextField(LLMProvider.custom.defaultBaseURL, text: $baseURL)
          .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
          .onSubmit { ai.setBaseURL(baseURL, provider) }
      }
      LabeledContent("Fast model") {
        TextField(provider.defaultModels.fast, text: $fast).multilineTextAlignment(.trailing)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .onSubmit { ai.setModel(fast, .fast, provider) }
      }
      LabeledContent("Smart model") {
        TextField(provider.defaultModels.smart, text: $smart).multilineTextAlignment(.trailing)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .onSubmit { ai.setModel(smart, .smart, provider) }
      }
      LabeledContent("Spent this month", value: String(format: "$%.2f of $80", env.aiStore.spentThisMonth()))
    } header: {
      Text("Coach AI")
    } footer: {
      Text(footer(provider))
    }
    .onAppear { load(provider) }
    .onChange(of: provider) { old, new in
      save(old)
      load(new)
    }
    .onDisappear { save(provider) }
  }

  private func footer(_ p: LLMProvider) -> String {
    if p == .anthropic, env.server.deliveredKey { return "Your key was added automatically from your home PC." }
    if !env.aiSettings.hasKey { return "Add a key to turn on AI explanations, the coach bot and Ask. Everything else works offline." }
    return "Fast runs during games; smart answers your questions. Leave blank for the defaults."
  }

  private func load(_ p: LLMProvider) {
    let ai = env.aiSettings
    key = ai.key(p)
    fast = ai.model(.fast, p)
    smart = ai.model(.smart, p)
    baseURL = ai.baseURL(p)
  }

  private func save(_ p: LLMProvider) {
    let ai = env.aiSettings
    if key != ai.key(p) { ai.setKey(key, for: p) }
    if fast != ai.model(.fast, p) { ai.setModel(fast, .fast, p) }
    if smart != ai.model(.smart, p) { ai.setModel(smart, .smart, p) }
    if baseURL != ai.baseURL(p) { ai.setBaseURL(baseURL, p) }
  }
}
