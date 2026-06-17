import SwiftUI
import UniformTypeIdentifiers

struct EmptyStateView: View {
    @EnvironmentObject private var manager: SignatureManager
    @Binding var showDrawing: Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)

            // Drop zone / icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargeted
                          ? Color.accentColor.opacity(0.08)
                          : Color.accentColor.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.5, dash: isDropTargeted ? [] : [5, 4])
                            )
                            .foregroundColor(Color.accentColor.opacity(isDropTargeted ? 0.5 : 0.2))
                    )
                    .animation(.easeOut(duration: 0.15), value: isDropTargeted)

                VStack(spacing: 8) {
                    Group {
                        if manager.isProcessing {
                            ProgressView()
                                .scaleEffect(1.2)
                                .frame(width: 80, height: 80)
                        } else if isDropTargeted {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(.accentColor)
                                .opacity(0.6)
                        } else {
                            if let img = NSImage(named: "AppIcon") {
                                Image(nsImage: img)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.accentColor)
                            } else {
                                Image(systemName: "signature")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(.accentColor)
                                    .opacity(0.6)
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: isDropTargeted)

                    if manager.isProcessing {
                        Text("Processing image...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                    } else {
                        Text(isDropTargeted ? "Drop to add signature" : "No signatures yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isDropTargeted ? .accentColor : .primary)
                            .accessibilityIdentifier("empty-state")

                        if !isDropTargeted {
                            Text("Choose a PNG, JPEG, or TIFF file\nor drag one here.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(20)
            }
            .frame(height: 130)
            .padding(.horizontal, 14)
            .onDrop(of: [.fileURL, .image, .png], isTargeted: $isDropTargeted) { providers in
                manager.handleDrop(providers: providers)
            }

            HStack(spacing: 12) {
                Button(action: { manager.openFilePicker() }) {
                    Label("Add File", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Add a signature image file")
                
                Button(action: { showDrawing = true }) {
                    Label("Draw", systemImage: "pencil.and.outline")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Draw new signature")
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 12)
        }
    }
}
