import ChessCoachKit
import PencilKit
import SwiftUI

/// The feedback sheet (spec W8): optional category, one text field, the screen you were on
/// (mark it up or leave it out), and a clear switch for the diagnostic details.
struct FeedbackSheet: View {
  let center: FeedbackCenter
  @State var draft: FeedbackDraft
  @State private var sending = false
  @State private var sent = false
  @State private var showIncluded = false
  @State private var markingUp = false
  @FocusState private var textFocused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          if sent {
            sentView
          } else {
            form
          }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.l)
      }
      .background(Palette.surfaceBase.ignoresSafeArea())
      .navigationTitle(sent ? "" : "Send feedback")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(sent ? "Close" : "Cancel") { close() }.accessibilityIdentifier("feedback-cancel")
        }
        if !sent {
          ToolbarItem(placement: .confirmationAction) {
            Button("Send") { send() }
              .disabled(!draft.canSend || sending)
              .accessibilityIdentifier("feedback-send")
          }
        }
      }
    }
    .tint(Palette.sage)
    .onAppear { textFocused = true }
    .onChange(of: draft.text) { _, new in UserDefaults.standard.set(new, forKey: FeedbackDraft.draftKey) }
    .fullScreenCover(isPresented: $markingUp) {
      if let shot = draft.screenshot {
        MarkupEditor(image: shot) { draft.screenshot = $0 }
      }
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: Spacing.l) {
      HStack(spacing: Spacing.s) {
        ForEach([FeedbackReport.Category.bug, .confusing, .idea, .praise], id: \.self) { c in
          Chip(title: c.title, isSelected: draft.category == c) { draft.category = draft.category == c ? .none : c }
            .accessibilityIdentifier("feedback-cat-\(c.rawValue)")
        }
      }
      TextField("What happened? What did you expect?", text: $draft.text, axis: .vertical)
        .lineLimit(4...10)
        .font(Typography.body)
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous).fill(Palette.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.75))
        .focused($textFocused)
        .accessibilityIdentifier("feedback-text")

      if let shot = draft.screenshot {
        HStack(alignment: .top, spacing: Spacing.m) {
          Image(uiImage: shot)
            .resizable().scaledToFit()
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Spacing.cornerSmall, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.75))
            .opacity(draft.includeScreenshot ? 1 : 0.35)
            .accessibilityLabel("Screenshot of the screen you were on")
          VStack(alignment: .leading, spacing: Spacing.s) {
            Toggle("Include screenshot", isOn: $draft.includeScreenshot).font(Typography.callout)
              .accessibilityIdentifier("feedback-include-shot")
            Button { markingUp = true } label: { Label("Highlight or hide parts", systemImage: "pencil.tip.crop.circle") }
              .font(Typography.callout).disabled(!draft.includeScreenshot)
          }
        }
      }

      VStack(alignment: .leading, spacing: Spacing.s) {
        Toggle("Include diagnostic details", isOn: $draft.includeDiagnostics).font(Typography.callout)
          .accessibilityIdentifier("feedback-include-diagnostics")
        DisclosureGroup("What's included?", isExpanded: $showIncluded) {
          Text(included).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Spacing.xs)
        }
        .font(Typography.caption)
      }
      Text("Your API key, email and anything you've typed elsewhere are never sent.")
        .font(Typography.caption).foregroundStyle(Palette.textTertiary)
    }
  }

  private var included: String {
    var lines = ["The screen you were on: \(draft.screen)"]
    if !draft.context.isEmpty { lines.append("Its state: " + draft.context.keys.sorted().joined(separator: ", ")) }
    lines.append("Your last \(center.breadcrumbs.lines.count) actions in the app (names and numbers, no text)")
    lines.append("App build \(FeedbackCenter.build), iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)")
    return lines.joined(separator: "\n")
  }

  private var sentView: some View {
    VStack(spacing: Spacing.l) {
      Image(systemName: "checkmark.circle.fill").font(Typography.symbol(54)).foregroundStyle(Palette.success)
        .accessibilityHidden(true)
      Text("Thanks, it's sent.").font(Typography.title).foregroundStyle(Palette.textPrimary)
      Text(PublicServer.shared.isAvailable
        ? "You can follow it in Settings → Your feedback. We'll mark it there when it's fixed."
        : "It's saved on your phone and goes out as soon as you're online. Follow it in Settings → Your feedback.")
        .font(Typography.body).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
      PrimaryButton(title: "Done", action: close)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Spacing.xxl)
    .accessibilityIdentifier("feedback-sent")
  }

  private func send() {
    sending = true
    let d = draft
    UserDefaults.standard.removeObject(forKey: FeedbackDraft.draftKey)
    Task {
      await center.submit(d)
      sending = false
      sent = true
    }
  }

  private func close() { dismiss() }
}

extension FeedbackReport.Category {
  var title: String {
    switch self {
    case .bug: "Bug"
    case .confusing: "Confusing"
    case .idea: "Idea"
    case .praise: "Praise"
    case .none: "Other"
    }
  }
}

/// Draw on the screenshot: highlight to point at something, black out to hide it.
private struct MarkupEditor: View {
  let image: UIImage
  let onDone: (UIImage) -> Void
  @State private var canvas = PKCanvasView()
  @State private var hiding = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        let size = fitted(in: proxy.size)
        ZStack {
          Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
          CanvasView(canvas: canvas, tool: tool).frame(width: size.width, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(Palette.surfaceSunken.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(flattened()); dismiss() } }
        ToolbarItemGroup(placement: .bottomBar) {
          Picker("Tool", selection: $hiding) {
            Label("Highlight", systemImage: "highlighter").tag(false)
            Label("Black out", systemImage: "rectangle.fill").tag(true)
          }
          .pickerStyle(.segmented)
          Button { canvas.undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
            .accessibilityLabel("Undo")
        }
      }
    }
  }

  private var tool: PKInkingTool {
    hiding ? PKInkingTool(.monoline, color: .black, width: 28) : PKInkingTool(.marker, color: .systemYellow, width: 22)
  }

  private func fitted(in box: CGSize) -> CGSize {
    let s = min(box.width / image.size.width, box.height / image.size.height)
    return CGSize(width: image.size.width * s, height: image.size.height * s)
  }

  private func flattened() -> UIImage {
    let bounds = canvas.bounds
    guard bounds.width > 0 else { return image }
    return UIGraphicsImageRenderer(size: image.size).image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
      canvas.drawing.image(from: bounds, scale: image.size.width / bounds.width)
        .draw(in: CGRect(origin: .zero, size: image.size))
    }
  }
}

private struct CanvasView: UIViewRepresentable {
  let canvas: PKCanvasView
  let tool: PKInkingTool

  func makeUIView(context: Context) -> PKCanvasView {
    canvas.drawingPolicy = .anyInput
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    canvas.tool = tool
    return canvas
  }

  func updateUIView(_ view: PKCanvasView, context: Context) { view.tool = tool }
}

/// Settings → Your feedback: what you've sent, what's waiting, and what's been fixed.
struct FeedbackListView: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    List {
      let pending = env.feedback.pending
      if !pending.isEmpty {
        Section("Waiting to send") {
          ForEach(pending) { r in row(r.text.isEmpty ? r.category.title : r.text, status: "Waiting", color: Palette.textTertiary) }
        }
      }
      Section {
        if env.feedback.reports.isEmpty {
          Text("Nothing sent yet. Tap the speech bubble on any screen to tell us what's working and what isn't.")
            .font(Typography.callout).foregroundStyle(Palette.textSecondary)
        }
        ForEach(env.feedback.reports) { r in
          row(r.text.isEmpty ? r.category.capitalized : r.text, status: statusText(r), color: r.status == "fixed" ? Palette.success : Palette.textSecondary)
        }
      } header: {
        Text("Sent")
      }
      Section {
        Button("Send new feedback") { env.feedback.open(source: "settings") }
      }
    }
    .navigationTitle("Your feedback")
    .task { await env.feedback.flush(); await env.feedback.refreshStatuses() }
  }

  private func statusText(_ r: FeedbackCenter.SentReport) -> String {
    switch r.status {
    case "fixed": r.fixed_in_build.map { "Fixed in build \($0)" } ?? "Fixed"
    case "wontfix": "Not planned"
    default: "Received"
    }
  }

  private func row(_ text: String, status: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(text).font(Typography.body).lineLimit(2)
      Text(status).font(Typography.caption.weight(.semibold)).foregroundStyle(color)
    }
    .accessibilityElement(children: .combine)
  }
}
