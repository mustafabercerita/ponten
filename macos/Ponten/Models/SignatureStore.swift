import AppKit
import Foundation

struct SignatureItem: Codable, Identifiable, Equatable {
    var id: UUID
    var filename: String
    var name: String?
}

struct UserSettings: Codable, Equatable {
    var autoPaste: Bool
    var launchAtLogin: Bool
    var removeBackground: Bool
    var globalShortcut: Int
    var showWhiteCanvas: Bool

    init(
        autoPaste: Bool = true,
        launchAtLogin: Bool = false,
        removeBackground: Bool = true,
        globalShortcut: Int = 0,
        showWhiteCanvas: Bool = true
    ) {
        self.autoPaste = autoPaste
        self.launchAtLogin = launchAtLogin
        self.removeBackground = removeBackground
        self.globalShortcut = globalShortcut
        self.showWhiteCanvas = showWhiteCanvas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        removeBackground = try container.decodeIfPresent(Bool.self, forKey: .removeBackground) ?? true
        globalShortcut = try container.decodeIfPresent(Int.self, forKey: .globalShortcut) ?? 0
        showWhiteCanvas = try container.decodeIfPresent(Bool.self, forKey: .showWhiteCanvas) ?? true
    }
}

struct IndexWrapper: Codable {
    var items: [SignatureItem]
    var activeID: UUID?
    var settings: UserSettings?
}

struct SignatureLoadResult {
    var items: [SignatureItem]
    var prunedCount: Int
}

// MARK: - Cross-platform JSON (camelCase write, case-insensitive read)

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private enum PontenJSON {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            guard let key = keys.last else {
                return AnyCodingKey(stringValue: "")!
            }
            let original = key.stringValue
            let camelCase = original.prefix(1).lowercased() + original.dropFirst()
            return AnyCodingKey(stringValue: camelCase) ?? key
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }
}

/// Persists signature image files and the index manifest on disk.
final class SignatureStore {

    let storageDirectory: URL

    private var indexPath: URL {
        storageDirectory.appendingPathComponent("index.json")
    }

    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    static func defaultStorageDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Ponten", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func load() -> SignatureLoadResult {
        if !FileManager.default.fileExists(atPath: indexPath.path) {
            let migrated = migrateLegacySignature()
            return SignatureLoadResult(items: migrated, prunedCount: 0)
        }

        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? PontenJSON.makeDecoder().decode(IndexWrapper.self, from: data) else {
            let rebuilt = rebuildFromPNGFiles(preservingSettingsFromCorruptIndex: true)
            return SignatureLoadResult(items: rebuilt, prunedCount: 0)
        }

        let fm = FileManager.default
        var loaded: [SignatureItem] = []
        for item in wrapper.items {
            let path = filePath(for: item.filename)
            if fm.fileExists(atPath: path.path) {
                loaded.append(item)
            }
        }

        var prunedCount = 0
        if loaded.count < wrapper.items.count {
            prunedCount = wrapper.items.count - loaded.count
            let prunedActiveID = wrapper.activeID.flatMap { id in
                loaded.contains(where: { $0.id == id }) ? id : loaded.first?.id
            }
            try? saveIndex(items: loaded, activeID: prunedActiveID, settings: wrapper.settings)
        }

        return SignatureLoadResult(items: loaded, prunedCount: prunedCount)
    }

    func loadImage(filename: String) -> NSImage? {
        NSImage(contentsOf: filePath(for: filename))
    }

    func loadActiveID() -> UUID? {
        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? PontenJSON.makeDecoder().decode(IndexWrapper.self, from: data) else {
            return nil
        }
        return wrapper.activeID
    }

    func loadSettings() -> UserSettings? {
        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? PontenJSON.makeDecoder().decode(IndexWrapper.self, from: data) else {
            return nil
        }
        return wrapper.settings
    }

    func saveIndex(items: [SignatureItem], activeID: UUID?, settings: UserSettings? = nil) throws {
        let wrapper = IndexWrapper(items: items, activeID: activeID, settings: settings)
        let data = try PontenJSON.makeEncoder().encode(wrapper)
        do {
            try data.write(to: indexPath, options: .atomic)
        } catch {
            if StorageError.isDiskFull(error) {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteOutOfSpaceError,
                    userInfo: [NSLocalizedDescriptionKey: "Not enough disk space to save signatures."]
                )
            }
            throw error
        }
    }

    func deleteFile(filename: String) {
        let path = filePath(for: filename)
        try? FileManager.default.removeItem(at: path)
    }

    func filePath(for filename: String) -> URL {
        storageDirectory.appendingPathComponent(filename)
    }

    func writePNG(data: Data, filename: String) throws {
        do {
            try data.write(to: filePath(for: filename), options: .atomic)
        } catch {
            if StorageError.isDiskFull(error) {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteOutOfSpaceError,
                    userInfo: [NSLocalizedDescriptionKey: "Not enough disk space to save signatures."]
                )
            }
            throw error
        }
    }

    func commitPNG(tempFilename: String, finalFilename: String) throws {
        let tempPath = filePath(for: tempFilename)
        let finalPath = filePath(for: finalFilename)
        let fm = FileManager.default

        if fm.fileExists(atPath: finalPath.path) {
            try fm.removeItem(at: finalPath)
        }
        try fm.moveItem(at: tempPath, to: finalPath)
    }

    // MARK: - Recovery & Migration

    private func rebuildFromPNGFiles(preservingSettingsFromCorruptIndex: Bool = false) -> [SignatureItem] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var loaded: [SignatureItem] = []
        for url in files where url.pathExtension.lowercased() == "png" {
            let filename = url.lastPathComponent
            if filename.hasSuffix(".tmp.png") { continue }

            if filename.lowercased() == "signature.png" {
                let id = UUID()
                let newFilename = "\(id.uuidString).png"
                let newPath = filePath(for: newFilename)
                do {
                    try fm.moveItem(at: url, to: newPath)
                } catch {
                    continue
                }
                loaded.append(SignatureItem(id: id, filename: newFilename, name: nil))
                continue
            }

            let stem = String(filename.dropLast(4))
            guard let id = UUID(uuidString: stem) else { continue }

            let item = SignatureItem(id: id, filename: filename, name: nil)
            loaded.append(item)
        }

        loaded.sort { $0.filename < $1.filename }

        if !loaded.isEmpty {
            let activeID = loaded.first?.id
            let settings = preservingSettingsFromCorruptIndex ? parseSettingsFromCorruptIndex() : nil
            try? saveIndex(items: loaded, activeID: activeID, settings: settings)
        }

        return loaded
    }

    private func parseSettingsFromCorruptIndex() -> UserSettings? {
        guard let data = try? Data(contentsOf: indexPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settingsDict = (json["settings"] ?? json["Settings"]) as? [String: Any] else {
            return nil
        }

        var settings = UserSettings()
        if let autoPaste = settingsDict["autoPaste"] as? Bool ?? settingsDict["AutoPaste"] as? Bool {
            settings.autoPaste = autoPaste
        }
        if let launchAtLogin = settingsDict["launchAtLogin"] as? Bool ?? settingsDict["LaunchAtLogin"] as? Bool {
            settings.launchAtLogin = launchAtLogin
        }
        if let removeBackground = settingsDict["removeBackground"] as? Bool ?? settingsDict["RemoveBackground"] as? Bool {
            settings.removeBackground = removeBackground
        }
        if let globalShortcut = settingsDict["globalShortcut"] as? Int ?? settingsDict["GlobalShortcut"] as? Int {
            settings.globalShortcut = globalShortcut
        }
        if let showWhiteCanvas = settingsDict["showWhiteCanvas"] as? Bool ?? settingsDict["ShowWhiteCanvas"] as? Bool {
            settings.showWhiteCanvas = showWhiteCanvas
        }
        return settings
    }

    private func migrateLegacySignature() -> [SignatureItem] {
        let oldPath = filePath(for: "signature.png")
        guard FileManager.default.fileExists(atPath: oldPath.path) else {
            return []
        }

        let id = UUID()
        let newItem = SignatureItem(id: id, filename: "signature.png")
        try? saveIndex(items: [newItem], activeID: id)
        return [newItem]
    }
}