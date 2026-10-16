import SwiftUI

/// Brief overlay notification — "Set logged ✓", "Skipped Lat Pulldown", etc.
/// Auto-dismisses. Use via the global `ToastCenter.shared.show(...)`.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String, kind: Toast.Kind = .info, duration: TimeInterval = 1.6) {
        dismissTask?.cancel()
        current = Toast(text: text, kind: kind)
        switch kind {
        case .success: Haptics.success()
        case .warning: Haptics.warning()
        case .error:   Haptics.error()
        case .info:    Haptics.light()
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await MainActor.run { self?.current = nil }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind: Equatable {
            case info, success, warning, error
        }
    }
}

/// View modifier — attach once at the root and any caller of
/// `ToastCenter.shared.show(...)` lights up the overlay.
struct ToastOverlay: ViewModifier {
    @ObservedObject var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = center.current {
                    toastView(toast)
                        .padding(.top, Spacing.xxl)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(AnimationToken.satisfying, value: center.current)
                }
            }
    }

    private func toastView(_ toast: ToastCenter.Toast) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: iconFor(toast.kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colorFor(toast.kind))
            Text(toast.text)
                .font(Typography.callout)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(Palette.paper)
        .overlay(Capsule().stroke(Palette.border, lineWidth: 0.5))
        .clipShape(Capsule())
        .shadow(color: Palette.ink.opacity(0.12), radius: 12, y: 4)
    }

    private func iconFor(_ k: ToastCenter.Toast.Kind) -> String {
        switch k {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    private func colorFor(_ k: ToastCenter.Toast.Kind) -> Color {
        switch k {
        case .info: return Palette.primary
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .error: return Palette.danger
        }
    }
}

extension View {
    /// Attach the toast overlay (typically once at RootView).
    func wcoachToasts() -> some View { modifier(ToastOverlay()) }
}
