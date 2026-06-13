import SwiftUI
import UniformTypeIdentifiers

/// Root view rendered inside the NSPopover.
struct MenuBarView: View {
    @EnvironmentObject private var manager: SignatureManager

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView()

                Divider()

                Group {
                    if manager.signatureImage != nil {
                        SignatureActiveView()
                    } else {
                        EmptyStateView()
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: manager.signatureImage != nil)

                Divider()

                FooterView()
            }
            .frame(width: 300)
            .background(Color(NSColor.windowBackgroundColor))

            // Toast notification overlay
            if let msg = manager.toastMessage {
                ToastView(message: msg)
                    .padding(.bottom, 14)
                    .zIndex(10)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: manager.toastMessage)
    }
}

// MARK: - Header

private struct HeaderView: View {
    var body: some View {
        HStack(spacing: 8) {
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
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

// MARK: - Active State

private struct SignatureActiveView: View {
    @EnvironmentObject private var manager: SignatureManager
    @State private var showFileImporter = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var isDropTargeted = false

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

                if let img = manager.signatureImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 100)
                        .padding(12)
                        .accessibilityLabel("Current signature preview")
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
                handleDrop(providers: providers)
            }

            // Error message
            if let err = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(err)
                        .font(.caption)
                }
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Primary: Sign button
            Button(action: {
                manager.copySignatureToClipboard()
            }) {
                Label("Sign", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 14)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Copy signature to clipboard")
            .accessibilityHint("Copies your signature image so you can paste it anywhere")

            // Secondary row: Change + Delete
            HStack(spacing: 16) {
                Button(action: { showFileImporter = true }) {
                    Label("Change", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Change signature file")

                Spacer()

                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("Remove", systemImage: "trash")
                        .font(.callout)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove saved signature")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.png, .jpeg, .tiff, .image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
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
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // MARK: File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        withAnimation { errorMessage = nil }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            importURL(url)
        case .failure(let error):
            withAnimation { errorMessage = error.localizedDescription }
        }
    }

    // MARK: Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Prefer file URL (preserves format)
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { self.importURL(url) }
            }
            return true
        }
        // Fallback: raw image data
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
            provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let nsImage = image as? NSImage else { return }
                DispatchQueue.main.async {
                    do {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + ".png")
                        guard let tiff = nsImage.tiffRepresentation,
                              let bitmap = NSBitmapImageRep(data: tiff),
                              let png = bitmap.representation(using: .png, properties: [:]) else { return }
                        try png.write(to: tempURL)
                        self.importURL(tempURL)
                    } catch {
                        withAnimation { self.errorMessage = error.localizedDescription }
                    }
                }
            }
            return true
        }
        return false
    }

    private func importURL(_ url: URL) {
        do {
            try manager.saveSignature(from: url)
            withAnimation { errorMessage = nil }
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    @EnvironmentObject private var manager: SignatureManager
    @State private var showFileImporter = false
    @State private var errorMessage: String?
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
                        if isDropTargeted {
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

                    Text(isDropTargeted ? "Drop to add signature" : "No signature saved yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDropTargeted ? .accentColor : .primary)

                    if !isDropTargeted {
                        Text("Choose a PNG, JPEG, or TIFF file\nor drag one here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .frame(height: 130)
            .padding(.horizontal, 14)
            .onDrop(of: [.fileURL, .image, .png], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            if let err = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(err).font(.caption)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 14)
                .transition(.opacity)
            }

            Button(action: { showFileImporter = true }) {
                Label("Add Signature", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 14)
            .accessibilityLabel("Add a signature image file")

            Spacer(minLength: 12)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.png, .jpeg, .tiff, .image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        withAnimation { errorMessage = nil }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            importURL(url)
        case .failure(let error):
            withAnimation { errorMessage = error.localizedDescription }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { self.importURL(url) }
        }
        return true
    }

    private func importURL(_ url: URL) {
        do {
            try manager.saveSignature(from: url)
            withAnimation { errorMessage = nil }
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Footer

private struct FooterView: View {
    @EnvironmentObject private var manager: SignatureManager
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 10) {
            // Launch at Login toggle
            Toggle(isOn: Binding(
                get: { manager.launchAtLogin },
                set: { manager.setLaunchAtLogin($0) }
            )) {
                Text("Launch at Login")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel("Launch Personal Signature at login")

            Spacer()

            // About
            Button(action: { showAbout = true }) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About Personal Signature")
            .popover(isPresented: $showAbout, arrowEdge: .bottom) {
                AboutView()
            }

            // Quit
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit Personal Signature")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - About

private struct AboutView: View {
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

            Link("View on GitHub →",
                 destination: URL(string: "https://github.com/mustafabercerita/personal-signature")!)
                .font(.caption)

            Text("MIT License · Open Source")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 240)
    }
}
