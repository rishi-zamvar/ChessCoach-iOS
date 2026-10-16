import SwiftUI

/// Background atmosphere. Stack from back to front:
///   1. Lavender canvas (`Palette.canvas`).
///   2. Two soft radial mesh blobs (sage top-leading, rose bottom-trailing).
///   3. Deterministic paper grain at ~5% alpha, baked once per size.
///
/// Sits behind every screen — pin once at the RootView.
///
/// IMPORTANT: built around GeometryReader so the offset blobs (Circles whose
/// frames overflow the viewport) cannot bubble their intrinsic size up to
/// siblings in a parent ZStack. Without the GR wrap, the 520pt-wide Circle
/// makes the parent ZStack believe it has 520pt of width to share, which
/// shifts sibling content off-screen on narrower devices. Found 2026-05-26.
struct BackgroundAtmosphere: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Palette.canvas

                // Mesh blob — sage, top-leading.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.meshSage, Palette.meshSage.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 320
                        )
                    )
                    .frame(width: size.width * 1.3, height: size.width * 1.3)
                    .position(x: size.width * 0.0, y: size.height * 0.05)
                    .blur(radius: 40)

                // Mesh blob — rose, bottom-trailing.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.meshRose, Palette.meshRose.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 320
                        )
                    )
                    .frame(width: size.width * 1.2, height: size.width * 1.2)
                    .position(x: size.width * 1.05, y: size.height * 0.78)
                    .blur(radius: 50)

                GrainOverlay()
                    .opacity(0.05)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

/// Deterministic noise rendered via Canvas. Stable across redraws because the
/// seed is fixed; cheap because Canvas draws at native resolution and the
/// pixel grid is coarse.
struct GrainOverlay: View {
    var density: CGFloat = 3.0
    var dotSize: CGFloat = 1.4
    var seed: UInt64 = 0xC0FFEE

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed: seed)
            let cols = Int(size.width / density)
            let rows = Int(size.height / density)
            for row in 0..<rows {
                for col in 0..<cols {
                    let r = rng.nextUnit()
                    guard r < 0.35 else { _ = rng.nextUnit(); continue }
                    let jitterX = (rng.nextUnit() - 0.5) * density * 0.6
                    let jitterY = (rng.nextUnit() - 0.5) * density * 0.6
                    let x = CGFloat(col) * density + jitterX
                    let y = CGFloat(row) * density + jitterY
                    let alpha = 0.30 + rng.nextUnit() * 0.55
                    let rect = CGRect(
                        x: x, y: y,
                        width: dotSize, height: dotSize
                    )
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(Palette.grainInk.opacity(alpha))
                    )
                }
            }
        }
    }
}

/// Tiny xorshift PRNG so grain is repeatable across redraws but not visually
/// uniform. Apple's `SystemRandomNumberGenerator` is non-deterministic.
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func nextUnit() -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return CGFloat(state & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}
