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

struct SignatureItem: Codable, Identifiable, Equatable {
    var id: UUID
    var filename: String
    var name: String?
}

struct IndexWrapper: Codable {
    var items: [SignatureItem]
    var activeID: UUID?
}

/// Persists and vends signature images.
final class SignatureManager: ObservableObject {

    static let shared = SignatureManager()

    // MARK: - Published State

    @Published private(set) var signatures: [(item: SignatureItem, image: NSImage)] = []
    @Published var activeSignatureID: UUID? {
        didSet {
            saveIndex()
        }
    }
    
    var signatureImage: NSImage? {
        guard let id = activeSignatureID else { return nil }
        return signatures.first(where: { $0.item.id == id })?.image
    }

    var signaturePath: URL? {
        guard let id = activeSignatureID, let item = signatures.first(where: { $0.item.id == id })?.item else { return nil }
        return storageDirectory.appendingPathComponent(item.filename)
    }

    @Published var toastMessage: String?
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false
    @Published var pendingImageToEdit: NSImage? = nil
    @Published var pendingEditSignatureID: UUID? = nil
    
    @Published var showWhiteCanvas: Bool = UserDefaults.standard.object(forKey: "ShowWhiteCanvas") == nil ? true : UserDefaults.standard.bool(forKey: "ShowWhiteCanvas") {
        didSet {
            UserDefaults.standard.set(showWhiteCanvas, forKey: "ShowWhiteCanvas")
        }
    }
    
    @Published var autoPaste: Bool = UserDefaults.standard.bool(forKey: "AutoPasteEnabled") {
        didSet {
            UserDefaults.standard.set(autoPaste, forKey: "AutoPasteEnabled")
        }
    }
    @Published var launchAtLogin: Bool = false
    @Published var globalShortcut: ShortcutChoice = ShortcutChoice(rawValue: UserDefaults.standard.integer(forKey: "GlobalShortcut")) ?? .optCmdS {
        didSet {
            UserDefaults.standard.set(globalShortcut.rawValue, forKey: "GlobalShortcut")
            GlobalShortcutManager.shared.updateShortcut(globalShortcut)
        }
    }

    private var toastTimer: Timer?

    // MARK: - Paths

    let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Ponten", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var indexPath: URL {
        storageDirectory.appendingPathComponent("index.json")
    }

    // MARK: - Init

    private init() {
        loadSignatures()
        loadLaunchAtLoginState()
    }

    // MARK: - Load

    private func loadSignatures() {
        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? JSONDecoder().decode(IndexWrapper.self, from: data) else {
            // Migration: Check if old signature.png exists
            let oldPath = storageDirectory.appendingPathComponent("signature.png")
            if FileManager.default.fileExists(atPath: oldPath.path) {
                let id = UUID()
                let newItem = SignatureItem(id: id, filename: "signature.png")
                if let img = NSImage(contentsOf: oldPath) {
                    signatures = [(newItem, img)]
                    activeSignatureID = id
                    saveIndex()
                }
            }
            return
        }

        var loaded: [(SignatureItem, NSImage)] = []
        for item in wrapper.items {
            let path = storageDirectory.appendingPathComponent(item.filename)
            if let img = NSImage(contentsOf: path) {
                loaded.append((item, img))
            }
        }
        signatures = loaded
        activeSignatureID = wrapper.activeID ?? loaded.first?.0.id
    }

    private func saveIndex() {
        let items = signatures.map { $0.item }
        let wrapper = IndexWrapper(items: items, activeID: activeSignatureID)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: indexPath, options: .atomic)
        }
    }

    private func loadLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Save

    func saveSignature(from sourceURL: URL, removeBackground: Bool = false) throws {
        guard let img = NSImage(contentsOf: sourceURL) else {
            throw SignatureError.invalidImage
        }
        
        if !img.hasPredominantlyWhiteOrTransparentEdges() {
            throw SignatureError.notWhiteBackground
        }
        
        try saveSignature(image: img, removeBackground: removeBackground, vectorize: true, overwriteID: nil)
    }

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
        let path = storageDirectory.appendingPathComponent(filename)
        
        try pngData.write(to: path, options: .atomic)

        let item = SignatureItem(id: targetID, filename: filename, name: existingItem?.name)
        
        let updateState = { [weak self] in
            guard let self = self else { return }
            if isOverwriting {
                if let idx = self.signatures.firstIndex(where: { $0.item.id == targetID }) {
                    self.signatures[idx] = (item, img)
                }
            } else {
                self.signatures.append((item, img))
            }
            if self.activeSignatureID == targetID {
                self.saveIndex()
            } else {
                self.activeSignatureID = targetID
            }
        }

        if Thread.isMainThread {
            updateState()
        } else {
            DispatchQueue.main.sync(execute: updateState)
        }
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
                self.pendingImageToEdit = image
            } else {
                self.showToast(SignatureError.invalidImage.localizedDescription)
            }
            
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
    }

    // MARK: - Drag & Drop

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Prefer file URL
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let self = self, let url = url else { return }
                DispatchQueue.main.async { self.importURL(url) }
            }
            return true
        }
        // Fallback to raw image data
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
            _ = provider.loadObject(ofClass: NSImage.self) { [weak self] image, _ in
                guard let self = self, let nsImage = image as? NSImage else { return }
                DispatchQueue.main.async {
                    self.pendingImageToEdit = nsImage
                }
            }
            return true
        }
        return false
    }

    func importURL(_ url: URL) {
        if let image = NSImage(contentsOf: url) {
            DispatchQueue.main.async {
                self.pendingImageToEdit = image
            }
        } else {
            DispatchQueue.main.async {
                self.errorMessage = SignatureError.invalidImage.localizedDescription
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

    // MARK: - Auto-Paste

    func pasteToActiveApp() {
        let src = CGEventSource(stateID: .hidSystemState)

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        
        // 0x09 is 'V', 0x37 is Command
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
        
        // Remove file from disk
        if let itemToRemove = signatures.first(where: { $0.item.id == id })?.item {
            let path = storageDirectory.appendingPathComponent(itemToRemove.filename)
            try? FileManager.default.removeItem(at: path)
        }
        
        signatures.removeAll { $0.item.id == id }
        if signatures.isEmpty {
            activeSignatureID = nil
        } else if deletedActiveSignature, let first = signatures.first {
            activeSignatureID = first.item.id
        } else {
            saveIndex()
        }
        // The index handles it. 
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
            let timer = Timer(timeInterval: 2.5, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.toastMessage = nil
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self?.toastTimer = timer
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

// MARK: - CoreImage Background Removal

import CoreImage
import CoreImage.CIFilterBuiltins

extension NSImage {
    /// Removes white background from a signature image, making the ink black and paper transparent.
    func removingWhiteBackground() -> NSImage? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ciImage = CIImage(bitmapImageRep: bitmap) else {
            return nil
        }
        
        // 1. Invert colors (White paper -> Black, Ink -> White-ish)
        // This will serve as our alpha mask (luminance-based mask).
        let invertFilter = CIFilter.colorInvert()
        invertFilter.inputImage = ciImage
        guard let maskImage = invertFilter.outputImage else { return nil }
        
        // 2. Blend original image over a transparent background using the mask
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = ciImage // Foreground: Original image (keeps original colors)
        blendFilter.backgroundImage = CIImage.empty() // Background: Transparent
        blendFilter.maskImage = maskImage // Mask: inverted image (white = opaque ink, black = transparent paper)
        
        guard let finalCIImage = blendFilter.outputImage else { return nil }
        
        let rep = NSCIImageRep(ciImage: finalCIImage)
        let finalImage = NSImage(size: rep.size)
        finalImage.addRepresentation(rep)
        return finalImage
    }
}

// MARK: - Image Validation and Vectorization

import Vision

extension NSImage {
    func hasPredominantlyWhiteOrTransparentEdges() -> Bool {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 10 && height > 10 else { return true }
        
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixelData,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let ctx = context else { return true }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        
        var edgePixelCount = 0
        var whiteOrTransparentCount = 0
        let margin = 2
        
        for y in 0..<height {
            for x in 0..<width {
                if x < margin || x >= width - margin || y < margin || y >= height - margin {
                    edgePixelCount += 1
                    let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                    let r = pixelData[offset]
                    let g = pixelData[offset + 1]
                    let b = pixelData[offset + 2]
                    let a = pixelData[offset + 3]
                    
                    if a < 10 {
                        whiteOrTransparentCount += 1
                    } else if r > 240 && g > 240 && b > 240 {
                        whiteOrTransparentCount += 1
                    }
                }
            }
        }
        
        guard edgePixelCount > 0 else { return true }
        let ratio = Double(whiteOrTransparentCount) / Double(edgePixelCount)
        return ratio > 0.8
    }
    
    func replacingWithVectorizedStroke() -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        
        guard let whiteBgImage = context.makeImage() else { return nil }
        
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = true
        
        let handler = VNImageRequestHandler(cgImage: whiteBgImage, options: [:])
        try? handler.perform([request])
        
        guard let observation = request.results?.first else { return nil }
        
        let normalizedPath = observation.normalizedPath
        var transform = CGAffineTransform(scaleX: CGFloat(width), y: CGFloat(height))
        guard let scaledPath = normalizedPath.copy(using: &transform) else { return nil }
        
        let newImage = NSImage(size: NSSize(width: width, height: height))
        newImage.lockFocus()
        
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(scaledPath)
            ctx.fillPath(using: .evenOdd)
        }
        
        newImage.unlockFocus()
        return newImage
    }
}
