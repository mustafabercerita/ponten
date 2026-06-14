import SwiftUI

// MARK: - Primary Button Style

/// Accent-colored primary action button with press animation.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isEnabled ? .white : Color.white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled
                          ? Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1.0)
                          : Color.accentColor.opacity(0.35))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

/// Subtle secondary action button (no background, muted color).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary.opacity(configuration.isPressed ? 0.5 : 1.0))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Toast View

/// Dark pill notification that appears at the bottom of the popover.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(message.contains("✓") ? .green : .orange)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        )
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
    }
}
