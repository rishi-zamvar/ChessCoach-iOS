import UIKit

/// Single ingress point for haptic feedback. Calls are cheap to ignore on
/// older devices that don't support Taptic Engine. Use cases:
///   - `.light`: chip tap, stepper, secondary button
///   - `.medium`: primary button, sheet present
///   - `.success`: set logged, feedback sent, onboarding done
///   - `.warning`: failure-reason sheet opened
///   - `.error`: network error, validation fail
///   - `.selection`: stepper increment/decrement, picker change
@MainActor
enum Haptics {
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy()   { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func soft()    { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func rigid()   { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
