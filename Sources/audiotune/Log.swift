import Foundation

/// Dead-simple file + stderr logger so we can inspect Core Audio results,
/// including from launches where stdout isn't attached to a terminal.
///
/// The log lives in the standard `~/Library/Logs` location (not the user's
/// Documents folder) and is size-capped: once it exceeds `maxBytes` it is
/// rotated to a single `.1` backup, so it can never grow without bound.
enum Log {
    /// Rotate once the log passes this size; one previous file is kept.
    private static let maxBytes: UInt64 = 1_000_000 // 1 MB

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AudioTune", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("audiotune.log")
    }()

    private static var rotatedURL: URL { fileURL.appendingPathExtension("1") }

    private static let queue = DispatchQueue(label: "com.zjzack.audiotune.log")

    static func msg(_ items: Any...) {
        let line = items.map { "\($0)" }.joined(separator: " ")
        let stamped = "[\(timestamp())] \(line)\n"
        FileHandle.standardError.write(Data(stamped.utf8))
        queue.async {
            guard let data = stamped.data(using: .utf8) else { return }
            rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// Must be called on `queue`.
    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64, size > maxBytes else { return }
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: fileURL, to: rotatedURL)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
