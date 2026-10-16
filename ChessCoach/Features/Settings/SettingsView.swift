import ChessCoachKit
import SwiftUI

/// Settings: profile (retake onboarding), chess.com username, board look, sound, AI status.
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
  @State private var username = ""
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
        Section("chess.com") {
          TextField("Username", text: $username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { analysis.username = username.trimmingCharacters(in: .whitespaces) }
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
            Button("Hear the coach") { CoachSpeaker.shared.say("Take your time. Checks, captures, threats. What is their last move up to?") }
            if !CoachSpeaker.shared.voiceName.hasPrefix("Aman") || !CoachSpeaker.shared.hasNaturalVoice {
              Text("The coach speaks as Aman. For the best quality, download it on this iPhone: Settings → Accessibility → Spoken Content → Voices → English → India → Aman (Enhanced).")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        if env.server.hasKey {
          Section("Coach AI & home PC") {
            LabeledContent("Home PC", value: serverText)
            LabeledContent("AI key", value: "Ready (\(env.server.keyID ?? "—"))")
            LabeledContent("Spent this month", value: String(format: "$%.2f of $80", env.aiStore.spentThisMonth()))
            LabeledContent("On-device model", value: OnDeviceExplainer.isAvailable ? "Available" : "Not on this device")
            Button("Check now") { Task { await env.server.refresh() } }
          }
        }
        Section {
          Text("ChessCoach · engines: Stockfish 17, Maia-1100 (Lc0) · puzzles & openings: Lichess (CC0)")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
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

  private var serverText: String {
    switch env.server.status {
    case .online(let v): "Connected (v\(v))"
    case .checking: "Checking…"
    case .offline: "Not reachable"
    case .unknown: "—"
    }
  }

  private func commit() {
    let trimmed = username.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty { analysis.username = trimmed }
  }
}
