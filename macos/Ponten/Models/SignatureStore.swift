import AppKit
import Foundation

struct SignatureItem: Codable, Identifiable, Equatable {
    var id: UUID
    var filename: String
    var name: String?
}

struct UserSettings: Codable, Equatable {
    var autoPaste: Bool = false
}

struct IndexWrapper: Codable {
    var items: [SignatureItem]
    var activeID: UUID?
    var settings: UserSettings?
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

    func load() -> [(SignatureItem, NSImage)] {
        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? JSONDecoder().decode(IndexWrapper.self, from: data) else {
            return migrateLegacySignature()
        }

        var loaded: [(SignatureItem, NSImage)] = []
        for item in wrapper.items {
            let path = filePath(for: item.filename)
            if let img = NSImage(contentsOf: path) {
                loaded.append((item, img))
            }
        }

        if loaded.count < wrapper.items.count {
            let prunedItems = loaded.map { $0.0 }
            let prunedActiveID = wrapper.activeID.flatMap { id in
                prunedItems.contains(where: { $0.id == id }) ? id : prunedItems.first?.id
            }
            try? saveIndex(items: prunedItems, activeID: prunedActiveID)
        }

        return loaded
    }

    func loadActiveID() -> UUID? {
        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? JSONDecoder().decode(IndexWrapper.self, from: data) else {
            return nil
        }
        return wrapper.activeID
    }

    func loadSettings() -> UserSettings? {
        guard let data = try? Data(contentsOf: indexPath),
              let wrapper = try? JSONDecoder().decode(IndexWrapper.self, from: data) else {
            return nil
        }
        return wrapper.settings
    }

    func saveIndex(items: [SignatureItem], activeID: UUID?, settings: UserSettings? = nil) throws {
        let wrapper = IndexWrapper(items: items, activeID: activeID, settings: settings)
        let data = try JSONEncoder().encode(wrapper)
        try data.write(to: indexPath, options: .atomic)
    }

    func deleteFile(filename: String) {
        let path = filePath(for: filename)
        try? FileManager.default.removeItem(at: path)
    }

    func filePath(for filename: String) -> URL {
        storageDirectory.appendingPathComponent(filename)
    }

    func writePNG(data: Data, filename: String) throws {
        try data.write(to: filePath(for: filename), options: .atomic)
    }

    // MARK: - Migration

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