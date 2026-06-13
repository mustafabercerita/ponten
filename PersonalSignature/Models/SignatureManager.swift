import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

/// Persists and vends the active signature image.
/// Storage: the PNG is copied into ~/Library/Application Support/PersonalSignature/signature.png
final class SignatureManager: ObservableObject {

    static let shared = SignatureManager()

    // MARK: - Published State

    @Published private(set) var signatureImage: NSImage?
    @Published var toastMessage: String?
    @Published var launchAtLogin: Bool = false

    private var toastTimer: Timer?

    // MARK: - Paths

    private let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("PersonalSignature", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var signaturePath: URL {
        storageDirectory.appendingPathComponent("signature.png")
    }

    // MARK: - Init

    private init() {
        loadSignature()
        loadLaunchAtLoginState()
    }

    // MARK: - Load

    private func loadSignature() {
        guard FileManager.default.fileExists(atPath: signaturePath.path),
              let img = NSImage(contentsOf: signaturePath) else { return }
        signatureImage = img
    }

    private func loadLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Save

    /// Copies the user-chosen image file into the app's storage directory (re-encoded as PNG).
    func saveSignature(from sourceURL: URL) throws {
        guard let img = NSImage(contentsOf: sourceURL) else {
            throw SignatureError.invalidImage
        }

        guard let tiff = img.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SignatureError.encodingFailed
        }

        try pngData.write(to: signaturePath, options: .atomic)

        DispatchQueue.main.async { [weak self] in
            self?.signatureImage = img
        }
    }

    // MARK: - File Picker

    @MainActor
    func openFilePicker() {
        let panel = NSOpenPanel()
        // Allowed types are typically UTType but we can specify them as NSOpenPanel properties or allowedContentTypes if imported UTType
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose your signature image"

        // Crucial for menu bar apps: bring to front so the panel isn't hidden behind other apps
        NSApp.activate(ignoringOtherApps: true)

        if panel.runModal() == .OK, let url = panel.url {
            // Need to handle security scoped resource if it's from outside sandbox (though macOS non-sandboxed doesn't strictly need it, good practice)
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            
            do {
                try saveSignature(from: url)
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    // MARK: - Copy to Clipboard

    @discardableResult
    func copySignatureToClipboard() -> Bool {
        guard let image = signatureImage else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([image])

        if success {
            showToast("Signature copied to clipboard ✓")
        } else {
            showToast("Failed to copy — try again.")
        }
        return success
    }

    // MARK: - Delete

    func deleteSignature() {
        try? FileManager.default.removeItem(at: signaturePath)
        DispatchQueue.main.async { [weak self] in
            self?.signatureImage = nil
        }
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            DispatchQueue.main.async { [weak self] in
                self?.launchAtLogin = enabled
            }
        } catch {
            showToast("Could not change login item: \(error.localizedDescription)")
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastTimer?.invalidate()
        DispatchQueue.main.async { [weak self] in
            self?.toastMessage = message
            self?.toastTimer = Timer.scheduledTimer(
                withTimeInterval: 2.5,
                repeats: false
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.toastMessage = nil
                }
            }
        }
    }
}

// MARK: - Errors

enum SignatureError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:   return "The selected file is not a valid image."
        case .encodingFailed: return "Failed to process the image. Try a different file."
        }
    }
}
