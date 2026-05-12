import Foundation

public enum PathClassification: Sendable {
    case safe
    case cautionary
    case systemProtected
    case userData
}

public struct PathClassifier: Sendable {
    public init() {}

    private static let sipProtectedPrefixes: Set<String> = [
        "/System",
        "/usr/bin",
        "/usr/lib",
        "/usr/sbin",
        "/usr/share",
        "/bin",
        "/sbin",
    ]

    private static let safeDeletionPrefixes: Set<String> = [
        "/Library/Caches",
        "/var/log",
    ]

    private static let cautionaryPrefixes: Set<String> = [
        "/Library/Application Support",
        "/Library/Preferences",
    ]

    public func classify(_ path: URL) -> PathClassification {
        let standardized = path.standardizedFileURL.path

        if Self.sipProtectedPrefixes.contains(where: { standardized.hasPrefix($0) }) {
            return .systemProtected
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let homeSafePrefixes = [
            "\(homeDir)/Library/Caches",
            "\(homeDir)/Library/Logs",
            "\(homeDir)/Library/Mail",
        ]

        if homeSafePrefixes.contains(where: { standardized.hasPrefix($0) }) {
            return .safe
        }

        if Self.safeDeletionPrefixes.contains(where: { standardized.hasPrefix($0) }) {
            return .safe
        }

        let homeCautionaryPrefixes = [
            "\(homeDir)/Library/Application Support",
            "\(homeDir)/Library/Preferences",
            "\(homeDir)/Library/Containers",
        ]

        if homeCautionaryPrefixes.contains(where: { standardized.hasPrefix($0) }) {
            return .cautionary
        }

        if Self.cautionaryPrefixes.contains(where: { standardized.hasPrefix($0) }) {
            return .cautionary
        }

        let userDataPrefixes = [
            "\(homeDir)/Documents",
            "\(homeDir)/Desktop",
            "\(homeDir)/Pictures",
            "\(homeDir)/Music",
            "\(homeDir)/Movies",
        ]

        if userDataPrefixes.contains(where: { standardized.hasPrefix($0) }) {
            return .userData
        }

        return .cautionary
    }

    public func isWritable(_ path: URL) -> Bool {
        let classification = classify(path)
        return classification != .systemProtected
    }

    public func containsSymlinkEscape(_ path: URL) -> Bool {
        let resolved = path.resolvingSymlinksInPath().path
        let original = path.standardizedFileURL.path
        return resolved != original
    }
}
