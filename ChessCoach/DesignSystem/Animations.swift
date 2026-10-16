import SwiftUI

/// Animation vocabulary. Always springs; calm but never sluggish.
enum AnimationToken {
    /// Quick UI nudges (chip taps, button press).
    static let quick: Animation = .spring(response: 0.28, dampingFraction: 0.85)
    /// Page transitions, sheet presentations.
    static let medium: Animation = .spring(response: 0.45, dampingFraction: 0.82)
    /// Slow, satisfying state changes (set logged, recommendation arrives).
    static let satisfying: Animation = .spring(response: 0.55, dampingFraction: 0.78)
    /// Default for any state mutation that doesn't warrant attention.
    static let subtle: Animation = .easeInOut(duration: 0.18)
    /// Long, organic breath — used for the AI recommendation card's pulse.
    static let breath: Animation = .easeInOut(duration: 3.2).repeatForever(autoreverses: true)
}

// MARK: - Pulse on tap

extension View {
    /// Soft scale-and-release for affordance feedback on any tappable element.
    func pulseOnTap() -> some View {
        modifier(PulseOnTap())
    }
}

struct PulseOnTap: ViewModifier {
    @State private var pressed: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(AnimationToken.quick, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
    }
}

// MARK: - Breathing pulse (the AI card)

extension View {
    /// Slow scale breath for hero content that's "alive" (the recommendation).
    func breathingPulse(amplitude: CGFloat = 0.01) -> some View {
        modifier(BreathingPulse(amplitude: amplitude))
    }
}

struct BreathingPulse: ViewModifier {
    let amplitude: CGFloat
    @State private var inhale = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(inhale ? 1 + amplitude : 1 - amplitude)
            .animation(AnimationToken.breath, value: inhale)
            .onAppear { inhale = true }
    }
}

// MARK: - Staggered cascade reveal

extension View {
    /// Staggered fade-up on appear. Pass the item's index in its list and the
    /// list's total count; this view will fade up after `index * stride` seconds.
    func cascadeReveal(index: Int, stride: Double = 0.06) -> some View {
        modifier(CascadeReveal(index: index, stride: stride))
    }
}

struct CascadeReveal: ViewModifier {
    let index: Int
    let stride: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                let delay = Double(index) * stride
                withAnimation(AnimationToken.satisfying.delay(delay)) {
                    visible = true
                }
            }
    }
}
