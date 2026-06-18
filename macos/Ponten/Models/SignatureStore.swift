import AppKit
import Foundation

struct SignatureItem: Codable, Identifiable, Equatable {
    var id: UUID
    var filename: String
    var name: String?
}

struct UserSettings: Codable, Equatable {
    var autoPaste: Bool = true
    var launchAtLogin: Bool = false
    var removeBackground: Bool = true
}

struct IndexWrapper: Codable {
    var items: [SignatureItem]
    var activeID: UUID?
    var settings: UserSettings?
}

struct SignatureLoadResult {
    var signatures: [(SignatureItem, NSImage)]
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
            return SignatureLoadResult(signatures: migrated, prunedCount: 0)
        }

        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? PontenJSON.makeDecoder().decode(IndexWrapper.self, from: data) else {
            let rebuilt = rebuildFromPNGFiles()
            return SignatureLoadResult(signatures: rebuilt, prunedCount: 0)
        }

        var loaded: [(SignatureItem, NSImage)] = []
        for item in wrapper.items {
            let path = filePath(for: item.filename)
            if let img = NSImage(contentsOf: path) {
                loaded.append((item, img))
            }
        }

        var prunedCount = 0
        if loaded.count < wrapper.items.count {
            prunedCount = wrapper.items.count - loaded.count
            let prunedItems = loaded.map { $0.0 }
            let prunedActiveID = wrapper.activeID.flatMap { id in
                prunedItems.contains(where: { $0.id == id }) ? id : prunedItems.first?.id
            }
            try? saveIndex(items: prunedItems, activeID: prunedActiveID, settings: wrapper.settings)
        }

        return SignatureLoadResult(signatures: loaded, prunedCount: prunedCount)
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

    private func rebuildFromPNGFiles() -> [(SignatureItem, NSImage)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var loaded: [(SignatureItem, NSImage)] = []
        for url in files where url.pathExtension.lowercased() == "png" {
            let filename = url.lastPathComponent
            if filename.hasSuffix(".tmp.png") { continue }

            let stem = String(filename.dropLast(4))
            let id = UUID(uuidString: stem) ?? UUID()
            guard let img = NSImage(contentsOf: url) else { continue }

            let item = SignatureItem(id: id, filename: filename, name: nil)
            loaded.append((item, img))
        }

        loaded.sort { $0.0.filename < $1.0.filename }

        if !loaded.isEmpty {
            let activeID = loaded.first?.0.id
            try? saveIndex(items: loaded.map(\.0), activeID: activeID)
        }

        return loaded
    }

    private func migrateLegacySignature() -> [(SignatureItem, NSImage)] {
        let oldPath = filePath(for: "signature.png")
        guard FileManager.default.fileExists(atPath: oldPath.path),
              let img = NSImage(contentsOf: oldPath) else {
            return []
        }

        let id = UUID()
        let newItem = SignatureItem(id: id, filename: "signature.png")
        try? saveIndex(items: [newItem], activeID: id)
        return [(newItem, img)]
    }
}