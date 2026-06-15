import SwiftUI
import UniformTypeIdentifiers

struct SignatureActiveView: View {
    @EnvironmentObject private var manager: SignatureManager
    @Binding var showDrawing: Bool
    @State private var showDeleteConfirm = false
    @State private var isDropTargeted = false
    @State private var signatureToRename: UUID? = nil
    @State private var newSignatureName: String = ""
    @State private var showRenameAlert = false

    var body: some View {
        VStack(spacing: 12) {
            // Preview area (also a drop target)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : Color.accentColor.opacity(0.2),
                                lineWidth: isDropTargeted ? 2 : 1
                            )
                    )
                    .animation(.easeOut(duration: 0.15), value: isDropTargeted)

                if manager.isProcessing {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Processing image...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !manager.signatures.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(manager.signatures, id: \.item.id) { sig in
                                Button(action: {
                                    manager.activeSignatureID = sig.item.id
                                    manager.copySignatureToClipboard()
                                }) {
                                    VStack(spacing: 4) {
                                        Image(nsImage: sig.image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 240, maxHeight: 80)
                                            .padding(8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(manager.showWhiteCanvas ? Color.white : Color.clear)
                                            )
                                        
                                        Text(sig.item.name ?? "Signature")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .padding(.bottom, 6)
                                    }
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(manager.activeSignatureID == sig.item.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Edit") {
                                        manager.pendingEditSignatureID = sig.item.id
                                        manager.pendingImageToEdit = sig.image
                                    }
                                    Button("Rename") {
                                        signatureToRename = sig.item.id
                                        newSignatureName = sig.item.name ?? "Signature"
                                        showRenameAlert = true
                                    }
                                    Button("Delete", role: .destructive) {
                                        manager.deleteSignature(id: sig.item.id)
                                    }
                                }
                                .onDrag {
                                    let url = manager.storageDirectory.appendingPathComponent(sig.item.filename)
                                    return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                
                // White Canvas Toggle
                VStack {
                    HStack {
                        Spacer()
                        Toggle("White Canvas", isOn: $manager.showWhiteCanvas)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .padding(8)
                    }
                    Spacer()
                }

                // Drop hint overlay
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                    Text("Drop to replace")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .fontWeight(.medium)
                }
            }
            .frame(height: 116)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .onDrop(of: [.fileURL, .image, .png], isTargeted: $isDropTargeted) { providers in
                manager.handleDrop(providers: providers)
            }

            // Primary: Sign button
            Button(action: {
                manager.copySignatureToClipboard()
            }) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Text("Sign")
                    Spacer()
                    Text(manager.globalShortcut.description)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 14)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Copy signature to clipboard")
            .accessibilityHint("Copies your signature image so you can paste it anywhere")

            // Secondary row: Add, Draw, Delete
            HStack(spacing: 12) {
                Button(action: { manager.openFilePicker() }) {
                    Label("Add", systemImage: "photo")
                        .font(.callout)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Add signature file")
                
                Button(action: { showDrawing = true }) {
                    Label("Draw", systemImage: "pencil.and.outline")
                        .font(.callout)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Draw new signature")

                Spacer()

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("Remove", systemImage: "trash")
                        .font(.callout)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove active signature")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .confirmationDialog(
            "Remove Signature?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                manager.deleteSignature()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your saved signature.")
        }
        .alert("Rename Signature", isPresented: $showRenameAlert) {
            TextField("Signature Name", text: $newSignatureName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let id = signatureToRename {
                    manager.renameSignature(id: id, newName: newSignatureName)
                }
            }
        } message: {
            Text("Enter a label for this signature.")
        }
    }
}
