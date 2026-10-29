import ChessCoachKit
import Foundation
import Observation
import SwiftUI
import UIKit

/// In-app feedback (spec W8): what screen you're on, the last 50 app events, an offline outbox,
/// sending through the public server, and the status of what you've sent.
@MainActor
@Observable
final class FeedbackCenter {
  /// The screen in front of the user and its state (set by `.screen(_:context:)`).
  var screen = "today"
  var context: [String: JSONValue] = [:]
  /// Board screens open (shake is ignored while you're playing).
  var boardsOpen = 0
  /// Reports and their status from the server, newest first.
  private(set) var reports: [SentReport] = []
  /// A one-line prompt shown at the top of the app (screenshot offer, "fixed in this build").
  var prompt: Prompt?
  @ObservationIgnored let breadcrumbs = BreadcrumbSink(capacity: 50)
  @ObservationIgnored let outbox: FeedbackOutbox
  @ObservationIgnored private let telemetry: () -> Telemetry?
  @ObservationIgnored private var offeredScreenshotThisSession = false

  struct SentReport: Identifiable, Decodable, Equatable {
    var id: String
    var created: Double
    var category: String
    var text: String
    var screen: String
    var status: String
    var fixed_in_build: String?
  }

  struct Prompt: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var action: Action
    enum Action: Equatable { case reportScreen, showReports }
  }

  init(telemetry: @escaping () -> Telemetry?) {
    self.telemetry = telemetry
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("feedback-outbox")
    outbox = FeedbackOutbox(directory: dir)
    NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.offerAfterScreenshot() }
    }
  }

  static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
  static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
  /// TestFlight builds carry a sandbox receipt.
  static var isTestFlight: Bool { Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" }

  static let shakeKey = "feedback.shake"
  /// Shake to report: on by default only in TestFlight builds (Apple reserves shake for undo).
  static var shakeEnabled: Bool { UserDefaults.standard.object(forKey: shakeKey) as? Bool ?? isTestFlight }

  var pending: [FeedbackReport] { outbox.pending() }

  // MARK: - Opening the sheet

  /// Captures the screen first (so the sheet isn't in the shot), then shows the feedback sheet on top of everything.
  func open(source: String) {
    let shot = Self.captureScreen()
    telemetry()?.event("feedback.open", metadata: ["source": .string(source), "screen": .string(screen)])
    let draft = FeedbackDraft(screen: screen, context: context, screenshot: shot)
    let host = UIHostingController(rootView: FeedbackSheet(center: self, draft: draft))
    host.modalPresentationStyle = .pageSheet
    host.sheetPresentationController?.detents = [.large()]
    Self.topViewController()?.present(host, animated: true)
  }

  func shake() {
    guard Self.shakeEnabled, boardsOpen == 0 else { return }
    open(source: "shake")
  }

  private func offerAfterScreenshot() {
    guard !offeredScreenshotThisSession else { return }
    offeredScreenshotThisSession = true
    prompt = Prompt(text: "Report a problem with this screen?", action: .reportScreen)
  }

  // MARK: - Sending

  func submit(_ draft: FeedbackDraft) async {
    let report = FeedbackReport.make(
      id: UUID(), category: draft.category, text: draft.text, screen: draft.screen, context: draft.context,
      breadcrumbs: breadcrumbs.lines, build: Self.build, appVersion: Self.version,
      screenshotJPEG: draft.includeScreenshot ? draft.screenshot.flatMap(Self.jpeg) : nil, diagnostics: draft.includeDiagnostics)
    try? outbox.enqueue(report)
    telemetry()?.event("feedback.submit", metadata: [
      "category": .string(draft.category.rawValue), "screen": .string(draft.screen), "feedback_id": .string(report.id.uuidString),
      "diagnostics": .bool(draft.includeDiagnostics), "screenshot": .bool(draft.includeScreenshot),
    ])
    Haptics.success()
    await flush()
  }

  /// Sends whatever is waiting (launch, foreground, after a submit).
  func flush() async {
    guard PublicServer.shared.isAvailable else { return }
    for report in outbox.pending() {
      guard let body = try? JSONEncoder().encode(report),
        (try? await PublicServer.shared.send("POST", "/v1/feedback", body: body)) != nil
      else { continue }
      outbox.remove(report.id)
    }
  }

  /// Fetches the status of your reports, and says so once when one is fixed in the build you're running.
  func refreshStatuses() async {
    guard PublicServer.shared.isAvailable,
      let data = try? await PublicServer.shared.send("GET", "/v1/feedback"),
      let decoded = try? JSONDecoder().decode([String: [SentReport]].self, from: data)
    else { return }
    reports = decoded["reports"] ?? []
    let seenKey = "feedback.fixedSeen"
    var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
    let build = Int(Self.build) ?? 0
    if let fixed = reports.first(where: { $0.status == "fixed" && Int($0.fixed_in_build ?? "") ?? .max <= build && !seen.contains($0.id) }) {
      seen.insert(fixed.id)
      UserDefaults.standard.set(Array(seen), forKey: seenKey)
      prompt = Prompt(text: "Fixed in this build: \"\(fixed.text.prefix(40))\"", action: .showReports)
    }
  }

  /// Settings → Delete my data: removes this device's feedback on the server and queues the
  /// analytics profile for deletion, then forgets the profile on the phone.
  func deleteMyData() async -> Bool {
    let body = (try? JSONSerialization.data(withJSONObject: ["distinct_id": AnalyticsSetup.distinctID ?? ""])) ?? Data()
    guard PublicServer.shared.isAvailable, (try? await PublicServer.shared.send("POST", "/v1/privacy/delete", body: body)) != nil
    else { return false }
    for report in outbox.pending() { outbox.remove(report.id) }
    reports = []
    AnalyticsSetup.setConsent(.basic, profile: { [:] }, userID: { "" })
    telemetry()?.event("settings.change", metadata: ["key": .string("delete_my_data")])
    return true
  }

  // MARK: - Screen capture

  static func captureScreen() -> UIImage? {
    guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)
    else { return nil }
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    return renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
  }

  /// A JPEG under ~350 KB (the server caps reports at 700 KB of base64).
  static func jpeg(_ image: UIImage) -> Data? {
    let scale = min(1, 1200 / max(image.size.width * image.scale, image.size.height * image.scale))
    let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    for quality in [0.6, 0.45, 0.3] {
      if let data = resized.jpegData(compressionQuality: quality), data.count < 350_000 { return data }
    }
    return nil
  }

  static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// What the user is writing (before it becomes a FeedbackReport).
struct FeedbackDraft {
  var category: FeedbackReport.Category = .none
  var text = ""
  var screen: String
  var context: [String: JSONValue]
  var screenshot: UIImage?
  var includeScreenshot = true
  var includeDiagnostics = true

  init(screen: String, context: [String: JSONValue], screenshot: UIImage?) {
    self.screen = screen
    self.context = context
    self.screenshot = screenshot
    includeScreenshot = screenshot != nil
    if let saved = UserDefaults.standard.string(forKey: Self.draftKey) { text = saved }
  }

  static let draftKey = "feedback.draft"
  var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category != .none }
}

extension View {
  /// Names the screen for analytics (`screen.view`) and feedback context. Board screens pass `board: true`
  /// so shake-to-report stays out of the way while you play.
  func screen(_ name: String, context: [String: JSONValue] = [:], board: Bool = false) -> some View {
    modifier(ScreenModifier(name: name, context: context, board: board))
  }
}

private struct ScreenModifier: ViewModifier {
  let name: String
  let context: [String: JSONValue]
  let board: Bool
  @Environment(AppEnvironment.self) private var env

  func body(content: Content) -> some View {
    content
      .onAppear {
        env.feedback.screen = name
        env.feedback.context = context
        if board { env.feedback.boardsOpen += 1 }
        env.telemetry.event("screen.view", metadata: ["name": .string(name)])
      }
      .onDisappear { if board { env.feedback.boardsOpen = max(0, env.feedback.boardsOpen - 1) } }
      .onChange(of: context) { _, new in env.feedback.context = new }
  }
}

/// The feedback entry point: a speech-bubble icon (top bars of tabs and board screens).
struct FeedbackButton: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    Button { env.feedback.open(source: "button") } label: {
      Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
        .font(Typography.body)
        .foregroundStyle(Palette.sage)
        .frame(width: 44, height: 44)
    }
    .accessibilityLabel("Send feedback")
    .accessibilityIdentifier("open-feedback")
  }
}

/// Shake anywhere (unless a text field claims it for undo): motion events that nobody handled reach the window.
extension UIWindow {
  open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
    super.motionEnded(motion, with: event)
  }
}
