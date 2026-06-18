import AppKit
import ApplicationServices
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

    static let settingsDefaults: UserDefaults = {
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

    @Published private(set) var signatures: [(item: SignatureItem, image: NSImage?)] = []
    @Published var activeSignatureID: UUID?

    private var imageCache: [UUID: NSImage] = [:]

    var signatureImage: NSImage? {
        guard let id = activeSignatureID else { return nil }
        if let cached = imageCache[id] {
            return cached
        }
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

    @Published var isFileDialogOpen = false
    @Published var isDrawingSheetOpen = false
    @Published var isDeleteDialogOpen = false
    @Published var isRenameDialogOpen = false

    var isModalPresented: Bool {
        isFileDialogOpen
            || isDrawingSheetOpen
            || pendingImageToEdit != nil
            || isDeleteDialogOpen
            || isRenameDialogOpen
    }

    var onToastOutsidePopover: ((String) -> Void)?

    @Published var showWhiteCanvas: Bool = {
        let defaults = SignatureManager.settingsDefaults
        return defaults.object(forKey: "ShowWhiteCanvas") == nil ? true : defaults.bool(forKey: "ShowWhiteCanvas")
    }() {
        didSet {
            SignatureManager.settingsDefaults.set(showWhiteCanvas, forKey: "ShowWhiteCanvas")
            guard !isLoadingSettings else { return }
            saveIndex()
        }
    }

    @Published var autoPaste: Bool = {
        let defaults = SignatureManager.settingsDefaults
        if defaults.object(forKey: "AutoPasteEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "AutoPasteEnabled")
    }() {
        didSet {
            SignatureManager.settingsDefaults.set(autoPaste, forKey: "AutoPasteEnabled")
            guard !isLoadingSettings else { return }
            saveIndex()
        }
    }

    @Published var removeBackground: Bool = true {
        didSet {
            guard !isLoadingSettings else { return }
            saveIndex()
        }
    }

    @Published var launchAtLogin: Bool = false

    @Published var globalShortcut: ShortcutChoice = {
        ShortcutChoice(rawValue: SignatureManager.settingsDefaults.integer(forKey: "GlobalShortcut")) ?? .optCmdS
    }() {
        didSet {
            SignatureManager.settingsDefaults.set(globalShortcut.rawValue, forKey: "GlobalShortcut")
            GlobalShortcutManager.shared.updateShortcut(globalShortcut)
            guard !isLoadingSettings else { return }
            saveIndex()
        }
    }

    private var toastTimer: Timer?
    var toastDuration: TimeInterval = 2.5
    private var isLoadingSettings = false

    // MARK: - Storage

    private let store: SignatureStore

    var storageDirectory: URL {
        store.storageDirectory
    }

    // MARK: - Init

    init(store: SignatureStore = SignatureStore(storageDirectory: SignatureStore.defaultStorageDirectory())) {
        self.store = store
        loadSignatures()
        loadSettingsFromIndex()
    }

    // MARK: - Load

    private func loadSignatures() {
        let result = store.load()
        imageCache = [:]
        signatures = result.items.map { ($0, nil) }
        activeSignatureID = store.loadActiveID() ?? signatures.first?.item.id

        if result.prunedCount > 0 {
            let noun = result.prunedCount == 1 ? "signature" : "signatures"
            showToast("\(result.prunedCount) \(noun) removed — image file(s) missing")
        }
    }

    func image(for id: UUID) -> NSImage? {
        if let cached = imageCache[id] {
            return cached
        }
        guard let item = signatures.first(where: { $0.item.id == id })?.item,
              let img = store.loadImage(filename: item.filename) else {
            return nil
        }
        imageCache[id] = img
        if let index = signatures.firstIndex(where: { $0.item.id == id }) {
            signatures[index].image = img
        }
        return img
    }

    func ensureImageLoaded(for id: UUID) {
        _ = image(for: id)
    }

    private func currentSettings() -> UserSettings {
        UserSettings(
            autoPaste: autoPaste,
            launchAtLogin: launchAtLogin,
            removeBackground: removeBackground,
            globalShortcut: globalShortcut.rawValue,
            showWhiteCanvas: showWhiteCanvas
        )
    }

    @discardableResult
    private func saveIndex() -> Bool {
        let items = signatures.map { $0.item }
        do {
            try store.saveIndex(items: items, activeID: activeSignatureID, settings: currentSettings())
            return true
        } catch {
            showToast(StorageError.userFacingMessage(for: error, fallbackPrefix: "Failed to save signatures"))
            return false
        }
    }

    private func loadSettingsFromIndex() {
        guard let settings = store.loadSettings() else {
            loadLaunchAtLoginFromSystem()
            return
        }

        isLoadingSettings = true
        defer { isLoadingSettings = false }

        autoPaste = settings.autoPaste
        SignatureManager.settingsDefaults.set(autoPaste, forKey: "AutoPasteEnabled")
        removeBackground = settings.removeBackground

        if let shortcut = ShortcutChoice(rawValue: settings.globalShortcut) {
            globalShortcut = shortcut
            SignatureManager.settingsDefaults.set(shortcut.rawValue, forKey: "GlobalShortcut")
            GlobalShortcutManager.shared.updateShortcut(shortcut)
        }

        showWhiteCanvas = settings.showWhiteCanvas
        SignatureManager.settingsDefaults.set(showWhiteCanvas, forKey: "ShowWhiteCanvas")

        if E2EMode.isEnabled {
            launchAtLogin = settings.launchAtLogin
            return
        }

        if #available(macOS 13.0, *) {
            let systemEnabled = SMAppService.mainApp.status == .enabled
            if settings.launchAtLogin != systemEnabled {
                setLaunchAtLogin(settings.launchAtLogin)
            } else {
                launchAtLogin = settings.launchAtLogin
            }
        } else {
            launchAtLogin = settings.launchAtLogin
        }
    }

    private func loadLaunchAtLoginFromSystem() {
        guard !E2EMode.isEnabled else { return }
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

        if vectorize {
            if let vectorImg = img.replacingWithVectorizedStroke() {
                img = vectorImg
            } else {
                showToast("Vectorization failed — saved without cleanup.")
            }
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
        let tempFilename = "\(targetID.uuidString).tmp.png"
        try store.writePNG(data: pngData, filename: tempFilename)

        let item = SignatureItem(id: targetID, filename: filename, name: existingItem?.name)
        let previousSignatures = signatures
        let previousActiveID = activeSignatureID

        imageCache[targetID] = img

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

        guard saveIndex() else {
            signatures = previousSignatures
            activeSignatureID = previousActiveID
            store.deleteFile(filename: tempFilename)
            throw SignatureError.encodingFailed
        }

        do {
            try store.commitPNG(tempFilename: tempFilename, finalFilename: filename)
        } catch {
            signatures = previousSignatures
            activeSignatureID = previousActiveID
            store.deleteFile(filename: tempFilename)
            showToast(StorageError.userFacingMessage(for: error, fallbackPrefix: "Failed to save signature file"))
            throw SignatureError.encodingFailed
        }
    }

    // MARK: - File Picker

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
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard let image = NSImage(contentsOf: url) else {
            DispatchQueue.main.async {
                self.errorMessage = SignatureError.invalidImage.localizedDescription
            }
            return
        }

        DispatchQueue.main.async {
            self.acceptImportedImage(image)
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

    // MARK: - Active Signature

    func selectActiveSignature(id: UUID) {
        guard signatures.contains(where: { $0.item.id == id }) else { return }
        guard activeSignatureID != id else { return }
        activeSignatureID = id
        saveIndex()
    }

    // MARK: - Copy to Clipboard

    @discardableResult
    func copySignatureToClipboard() -> Bool {
        guard let id = activeSignatureID, image(for: id) != nil else { return false }

        if E2EMode.isEnabled {
            writeE2ECopyMarker()
            showToast("Signature copied to clipboard ✓")
            return true
        }

        guard let image = image(for: id) else { return false }

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
        guard AXIsProcessTrusted() else {
            showToast("Enable Accessibility access in System Settings to auto-paste.")
            return
        }

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
        guard let index = signatures.firstIndex(where: { $0.0.id == id }) else { return }
        var updated = signatures[index]
        updated.item.name = newName
        signatures[index] = updated
        saveIndex()
    }

    func deleteSignature(id targetID: UUID? = nil) {
        guard let id = targetID ?? activeSignatureID else { return }
        guard let itemToRemove = signatures.first(where: { $0.item.id == id })?.item else { return }

        let previousSignatures = signatures
        let previousActiveID = activeSignatureID
        let deletedActiveSignature = activeSignatureID == id

        signatures.removeAll { $0.item.id == id }
        imageCache.removeValue(forKey: id)
        if signatures.isEmpty {
            activeSignatureID = nil
        } else if deletedActiveSignature, let first = signatures.first {
            activeSignatureID = first.item.id
        }

        guard saveIndex() else {
            signatures = previousSignatures
            activeSignatureID = previousActiveID
            return
        }

        store.deleteFile(filename: itemToRemove.filename)
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
                self?.saveIndex()
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
            self.onToastOutsidePopover?(message)
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