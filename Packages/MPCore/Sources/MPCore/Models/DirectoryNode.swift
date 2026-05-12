import Foundation

public struct DirectoryNode: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
    public let children: [DirectoryNode]

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        size: Int64,
        isDirectory: Bool,
        children: [DirectoryNode] = []
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
    }

    public static func == (lhs: DirectoryNode, rhs: DirectoryNode) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
