import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let img = NSImage(named: "AppIcon") {
                    Image(nsImage: img)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundColor(.primary)
                } else {
                    Image(systemName: "signature")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal Signature")
                        .font(.headline)
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Text("Put your digital signature one click away from your menu bar.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Global shortcut: ⌥⌘S")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let url = URL(string: "https://github.com/mustafabercerita/personal-signature") {
                Link("View on GitHub →", destination: url)
                    .font(.caption)
            }

            Text("MIT License · Open Source")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 240)
    }
}
