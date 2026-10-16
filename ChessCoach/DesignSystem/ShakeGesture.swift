import SwiftUI
import UIKit

/// Shake-to-X anywhere in the app. UIKit's motion API surfaces through the
/// first responder's motionEnded; we install an invisible
/// UIViewControllerRepresentable as a sibling so it's always in the chain.
extension Notification.Name {
    static let deviceDidShake = Notification.Name("wcoach.device.didShake")
}

private final class ShakeListenerVC: UIViewController {
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

private struct ShakeListener: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { ShakeListenerVC() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

extension View {
    /// Fire `action` when the user shakes the device. Used for "shake to
    /// send feedback" — fast escape hatch when something feels off.
    func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeListener().allowsHitTesting(false).frame(width: 0, height: 0))
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}
