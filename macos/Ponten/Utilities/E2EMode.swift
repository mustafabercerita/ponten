import Foundation

/// End-to-end test harness configuration (mirrors Windows `E2EMode.cs`).
enum E2EMode {

    /// `true` when launched with `--e2e` or env `PONTEN_E2E=1`.
    static let isEnabled: Bool = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--e2e") { return true }
        if ProcessInfo.processInfo.environment["PONTEN_E2E"] == "1" { return true }
        return false
    }()

    /// Isolated storage directory from env `PONTEN_DATA_DIR` or `--data-dir` CLI args.
    static let dataDirectory: URL? = {
        if let env = ProcessInfo.processInfo.environment["PONTEN_DATA_DIR"],
           !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }

        let args = ProcessInfo.processInfo.arguments
        for index in args.indices {
            let arg = args[index]
            if arg.hasPrefix("--data-dir=") {
                let path = String(arg.dropFirst("--data-dir=".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            if arg == "--data-dir", index + 1 < args.count {
                let path = args[index + 1]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }()

    /// Stable UserDefaults suite name derived from the data directory path hash (E2E + data dir only).
    static let userDefaultsSuiteName: String? = {
        guard isEnabled, let dataDirectory else { return nil }
        let hash = stableHash(from: dataDirectory.path)
        return "com.ponten.e2e.\(hash)"
    }()

    private static func stableHash(from path: String) -> String {
        var hash: UInt32 = 5381
        for byte in path.lowercased().utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return String(format: "%08X", hash)
    }
}