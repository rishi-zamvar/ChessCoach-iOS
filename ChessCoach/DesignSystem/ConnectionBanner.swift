import SwiftUI

/// Slim status strip pinned to the top of a screen. Hidden while online;
/// shows a rose strip with `message` when offline. Tap calls `onRetry`.
struct ConnectionBanner: View {
    var isOnline: Bool
    var message: String = "Offline"
    var onRetry: (() -> Void)? = nil

    var body: some View {
        Group {
            if !isOnline {
                bannerView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AnimationToken.medium, value: isOnline)
    }

    private var bannerView: some View {
        Button {
            Haptics.light()
            onRetry?()
        } label: {
            HStack(spacing: Spacing.s) {
                Circle()
                    .fill(Palette.danger)
                    .frame(width: 8, height: 8)
                Text(message)
                    .font(Typography.caption)
                    .tracking(0.3)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if onRetry != nil {
                    Text("Retry")
                        .eyebrowStyle(Palette.danger)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Palette.danger.opacity(0.18))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.danger.opacity(0.35)).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(onRetry == nil)
    }
}
