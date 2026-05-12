import Foundation

enum AuditLog {
    private static let path = "/var/log/macpolish-helper.log"
    private static let maxBytes: UInt64 = 10 * 1024 * 1024
    private static let queue = DispatchQueue(label: "com.macpolish.helper.auditlog")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func record(
        action: String,
        success: Bool,
        paths: [String] = [],
        error: String? = nil
    ) {
        queue.sync {
            writeEntry(action: action, success: success, paths: paths, error: error)
        }
    }

    private static func writeEntry(
        action: String,
        success: Bool,
        paths: [String],
        error: String?
    ) {
        rotateIfNeeded()

        var entry: [String: Any] = [
            "ts": formatter.string(from: Date()),
            "action": action,
            "success": success,
        ]
        if !paths.isEmpty { entry["paths"] = paths }
        if let error { entry["error"] = error }

        guard let json = try? JSONSerialization.data(withJSONObject: entry, options: []),
              var line = String(data: json, encoding: .utf8) else { return }
        line.append("\n")
        guard let data = line.data(using: .utf8) else { return }

        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            FileManager.default.createFile(
                atPath: path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
        }
    }

    private static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              size > maxBytes else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
