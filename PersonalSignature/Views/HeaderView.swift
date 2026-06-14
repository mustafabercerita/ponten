import SwiftUI

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 8) {
            if let img = NSImage(named: "OriginalLogo") {
                Image(nsImage: img)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "signature")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
            }

            Text("Personal Signature")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // Version badge
            Text("v1.0")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.1))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal Signature version 1.0")
    }
}
