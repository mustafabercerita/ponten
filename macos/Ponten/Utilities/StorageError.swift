import Foundation

enum StorageError {
    static func isDiskFull(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == POSIXErrorCode.ENOSPC.rawValue {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDiskFull(underlying)
        }
        return false
    }

    static func userFacingMessage(for error: Error, fallbackPrefix: String) -> String {
        if isDiskFull(error) {
            return "Not enough disk space to save signatures."
        }
        return "\(fallbackPrefix): \(error.localizedDescription)"
    }
}