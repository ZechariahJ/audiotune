import Foundation

/// Dead-simple file + stderr logger so we can inspect Core Audio results,
/// including from launches where stdout isn't attached to a terminal.
enum Log {
    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/audiotune")
        return dir.appendingPathComponent("audiotune.log")
    }()

    private static let queue = DispatchQueue(label: "com.zjzack.audiotune.log")

    static func msg(_ items: Any...) {
        let line = items.map { "\($0)" }.joined(separator: " ")
        let stamped = "[\(timestamp())] \(line)\n"
        FileHandle.standardError.write(Data(stamped.utf8))
        queue.async {
            if let data = stamped.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? stamped.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
