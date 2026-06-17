import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

enum ShortcutChoice: Int, CaseIterable, Identifiable {
    case optCmdS = 0
    case ctrlCmdS = 1
    case shiftCmdS = 2

    var id: Int { rawValue }
    var description: String {
        switch self {
        case .optCmdS: return "⌥⌘S"
        case .ctrlCmdS: return "⌃⌘S"
        case .shiftCmdS: return "⇧⌘S"
        }
    }
}

/// Persists and vends signature images.
final class SignatureManager: ObservableObject {

    private static let settingsDefaults: UserDefaults = {
        if let suiteName = E2EMode.userDefaultsSuiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        return .standard
    }()

    static let shared = SignatureManager(
        store: SignatureStore(
            storageDirectory: E2EMode.dataDirectory ?? SignatureStore.defaultStorageDirectory()
        )
    )

    // MARK: - Published State

    @Published private(set) var signatures: [(item: SignatureItem, image: NSImage)] = []
    @Published var activeSignatureID: UUID?

    var signatureImage: NSImage? {
        guard let id = activeSignatureID else { return nil }
        return signatures.first(where: { $0.item.id == id })?.image
    }

    var signaturePath: URL? {
        guard let id = activeSignatureID,
              let item = signatures.first(where: { $0.item.id == id })?.item else { return nil }
        return store.filePath(for: item.filename)
    }

    @Published var toastMessage: String?
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false
    @Published var pendingImageToEdit: NSImage? = nil
    @Published var pendingEditSignatureID: UUID? = nil

    @Published var showWhiteCanvas: Bool = {
        let defaults = SignatureManager.settingsDefaults
        return defaults.object(forKey: "ShowWhiteCanvas") == nil ? true : defaults.bool(forKey: "ShowWhiteCanvas")
    }() {
        didSet {
            SignatureManager.settingsDefaults.set(showWhiteCanvas, forKey: "ShowWhiteCanvas")
        }
    }

    @Published var autoPaste: Bool = {
        SignatureManager.settingsDefaults.bool(forKey: "AutoPasteEnabled")
    }() {
        didSet {
            SignatureManager.settingsDefaults.set(autoPaste, forKey: "AutoPasteEnabled")
            if E2EMode.isEnabled {
                saveIndex()
            }
        }
    }
    @Published var launchAtLogin: Bool = false
    @Published var globalShortcut: ShortcutChoice = {
        ShortcutChoice(rawValue: SignatureManager.settingsDefaults.integer(forKey: "GlobalShortcut")) ?? .optCmdS
    }() {
        didSet {
            SignatureManager.settingsDefaults.set(globalShortcut.rawValue, forKey: "GlobalShortcut")
            GlobalShortcutManager.shared.updateShortcut(globalShortcut)
        }
    }

    private var toastTimer: Timer?
    var toastDuration: TimeInterval = 2.5

    // MARK: - Storage

    private let store: SignatureStore

    var storageDirectory: URL {
        store.storageDirectory
    }

    // MARK: - Init

    init(store: SignatureStore = SignatureStore(storageDirectory: SignatureStore.defaultStorageDirectory())) {
        self.store = store
        loadSignatures()
        loadLaunchAtLoginState()
    }

    // MARK: - Load

    private func loadSignatures() {
        signatures = store.load()
        activeSignatureID = store.loadActiveID() ?? signatures.first?.0.id

        if E2EMode.isEnabled, let settings = store.loadSettings() {
            autoPaste = settings.autoPaste
        }
    }

    private func saveIndex() {
        let items = signatures.map { $0.item }
        let settings = E2EMode.isEnabled ? UserSettings(autoPaste: autoPaste) : nil
        do {
            try store.saveIndex(items: items, activeID: activeSignatureID, settings: settings)
        } catch {
            showToast("Failed to save signatures: \(error.localizedDescription)")
        }
    }

    private func loadLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Save

    @MainActor
    func saveSignature(from sourceURL: URL, removeBackground: Bool = false) throws {
        guard let img = NSImage(contentsOf: sourceURL) else {
            throw SignatureError.invalidImage
        }

        if !img.hasPredominantlyWhiteOrTransparentEdges() {
            throw SignatureError.notWhiteBackground
        }

        try saveSignature(image: img, removeBackground: removeBackground, vectorize: true, overwriteID: nil)
    }

    @MainActor
    func saveSignature(image sourceImage: NSImage, removeBackground: Bool = false, vectorize: Bool = false, overwriteID: UUID? = nil) throws {
        var img = sourceImage

        if vectorize, let vectorImg = img.replacingWithVectorizedStroke() {
            img = vectorImg
        } else if removeBackground, let processed = img.removingWhiteBackground() {
            img = processed
        }

        var extractedPngData: Data?
        if let tiff = img.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            extractedPngData = bitmap.representation(using: .png, properties: [:])
        } else if let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            extractedPngData = bitmap.representation(using: .png, properties: [:])
        }

        guard let pngData = extractedPngData else {
            throw SignatureError.encodingFailed
        }

        let isOverwriting = overwriteID != nil
        let targetID = overwriteID ?? UUID()
        let existingItem = signatures.first(where: { $0.item.id == targetID })?.item

        let filename = existingItem?.filename ?? "\(targetID.uuidString).png"
        try store.writePNG(data: pngData, filename: filename)

        let item = SignatureItem(id: targetID, filename: filename, name: existingItem?.name)

        if isOverwriting {
            if let idx = signatures.firstIndex(where: { $0.item.id == targetID }) {
                signatures[idx] = (item, img)
            }
        } else {
            signatures.append((item, img))
        }

        if activeSignatureID != targetID {
            activeSignatureID = targetID
        }
        saveIndex()
    }

    // MARK: - File Picker

    @Published var isFileDialogOpen = false

    @MainActor
    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose your signature image"

        NSApp.activate(ignoringOtherApps: true)

        isFileDialogOpen = true
        let response = panel.runModal()
        isFileDialogOpen = false

        if response == .OK, let url = panel.url {
            let accessed = url.startAccessingSecurityScopedResource()

            if let image = NSImage(contentsOf: url) {
                if image.hasPredominantlyWhiteOrTransparentEdges() {
                    self.pendingImageToEdit = image
                } else {
                    self.showToast(SignatureError.notWhiteBackground.localizedDescription)
                }
            } else {
                self.showToast(SignatureError.invalidImage.localizedDescription)
            }

            if accessed { url.stopAccessingSecurityScopedResource() }
        }
    }

    // MARK: - Drag & Drop

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let self = self, let url = url else { return }
                DispatchQueue.main.async { self.importURL(url) }
            }
            return true
        }
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
            _ = provider.loadObject(ofClass: NSImage.self) { [weak self] image, _ in
                guard let self = self, let nsImage = image as? NSImage else { return }
                DispatchQueue.main.async {
                    self.acceptImportedImage(nsImage)
                }
            }
            return true
        }
        return false
    }

    func importURL(_ url: URL) {
        if let image = NSImage(contentsOf: url) {
            DispatchQueue.main.async {
                self.acceptImportedImage(image)
            }
        } else {
            DispatchQueue.main.async {
                self.errorMessage = SignatureError.invalidImage.localizedDescription
            }
        }
    }

    @MainActor
    private func acceptImportedImage(_ image: NSImage) {
        if image.hasPredominantlyWhiteOrTransparentEdges() {
            pendingImageToEdit = image
        } else {
            showToast(SignatureError.notWhiteBackground.localizedDescription)
        }
    }

    // MARK: - Copy to Clipboard

    @discardableResult
    func copySignatureToClipboard() -> Bool {
        guard signatureImage != nil else { return false }

        if E2EMode.isEnabled {
            writeE2ECopyMarker()
            showToast("Signature copied to clipboard ✓")
            return true
        }

        guard let image = signatureImage else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([image])

        if success {
            showToast("Signature copied to clipboard ✓")

            if autoPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.pasteToActiveApp()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
            }
        } else {
            showToast("Failed to copy — try again.")
        }
        return success
    }

    private func writeE2ECopyMarker() {
        guard let dataDirectory = E2EMode.dataDirectory else { return }
        let markerPath = dataDirectory.appendingPathComponent("e2e-last-copy.txt")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        do {
            try timestamp.write(to: markerPath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write E2E copy marker: \(error)")
        }
    }

    // MARK: - Auto-Paste

    func pasteToActiveApp() {
        let src = CGEventSource(stateID: .hidSystemState)

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)

        cmdDown?.flags = .maskCommand
        cmdUp?.flags = .maskCommand

        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Signatures Management

    func renameSignature(id: UUID, newName: String) {
        if let index = signatures.firstIndex(where: { $0.0.id == id }) {
            signatures[index].0.name = newName
            saveIndex()
        }
    }

    func deleteSignature(id targetID: UUID? = nil) {
        guard let id = targetID ?? activeSignatureID else { return }
        let deletedActiveSignature = activeSignatureID == id

        if let itemToRemove = signatures.first(where: { $0.item.id == id })?.item {
            store.deleteFile(filename: itemToRemove.filename)
        }

        signatures.removeAll { $0.item.id == id }
        if signatures.isEmpty {
            activeSignatureID = nil
        } else if deletedActiveSignature, let first = signatures.first {
            activeSignatureID = first.item.id
        }
        saveIndex()
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(_ enabled: Bool) {
        if E2EMode.isEnabled { return }
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
        let duration = toastDuration
        let presentToast = { [weak self] in
            guard let self else { return }
            self.toastMessage = message
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                self?.toastMessage = nil
            }
            RunLoop.main.add(timer, forMode: .common)
            self.toastTimer = timer
        }
        if Thread.isMainThread {
            presentToast()
        } else {
            DispatchQueue.main.async(execute: presentToast)
        }
    }
}

// MARK: - Errors

enum SignatureError: LocalizedError {
    case invalidImage
    case encodingFailed
    case notWhiteBackground

    var errorDescription: String? {
        switch self {
        case .invalidImage:   return "The selected file is not a valid image."
        case .encodingFailed: return "Failed to process the image. Try a different file."
        case .notWhiteBackground: return "Image edges must be predominantly white or transparent."
        }
    }
}