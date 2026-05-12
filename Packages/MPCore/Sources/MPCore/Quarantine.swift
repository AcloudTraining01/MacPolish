import Foundation

public actor Quarantine {
    private let baseURL: URL
    private let retentionDays: Int

    public init(retentionDays: Int = 7) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.baseURL = appSupport
            .appendingPathComponent("MacPolish")
            .appendingPathComponent("Quarantine")
        self.retentionDays = retentionDays
    }

    public func quarantine(_ paths: [URL]) throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let batchDir = baseURL.appendingPathComponent(timestamp)
        try FileManager.default.createDirectory(
            at: batchDir,
            withIntermediateDirectories: true
        )

        let manifest = QuarantineManifest(
            timestamp: .now,
            items: paths.map { .init(originalPath: $0.path, quarantinedName: $0.lastPathComponent) }
        )

        for path in paths {
            let destination = batchDir.appendingPathComponent(path.lastPathComponent)
            try FileManager.default.moveItem(at: path, to: destination)
        }

        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: batchDir.appendingPathComponent("manifest.json"))

        return batchDir
    }

    public func restore(batchDir: URL) throws {
        let manifestURL = batchDir.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(QuarantineManifest.self, from: data)

        for item in manifest.items {
            let quarantinedPath = batchDir.appendingPathComponent(item.quarantinedName)
            let originalPath = URL(fileURLWithPath: item.originalPath)

            let parentDir = originalPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )

            try FileManager.default.moveItem(at: quarantinedPath, to: originalPath)
        }

        try FileManager.default.removeItem(at: batchDir)
    }

    public func purgeExpired() throws {
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return }

        let contents = try FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.creationDateKey]
        )

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: .now
        )!

        for dir in contents {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: dir.path),
                  let created = attrs[.creationDate] as? Date,
                  created < cutoff else { continue }
            try FileManager.default.removeItem(at: dir)
        }
    }

    public func listBatches() throws -> [QuarantineBatch] {
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.creationDateKey]
        )

        return contents.compactMap { dir in
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(QuarantineManifest.self, from: data) else {
                return nil
            }
            return QuarantineBatch(directory: dir, manifest: manifest)
        }
    }
}

public struct QuarantineManifest: Codable, Sendable {
    public let timestamp: Date
    public let items: [QuarantinedItem]

    public struct QuarantinedItem: Codable, Sendable {
        public let originalPath: String
        public let quarantinedName: String
    }
}

public struct QuarantineBatch: Sendable {
    public let directory: URL
    public let manifest: QuarantineManifest
}
