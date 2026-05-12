import Foundation

public struct ScanItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let path: URL
    public let name: String
    public let size: Int64
    public let category: ScanCategory
    public let riskLevel: RiskLevel
    public let lastModified: Date?
    public let explanation: String?
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        path: URL,
        name: String,
        size: Int64,
        category: ScanCategory,
        riskLevel: RiskLevel = .safe,
        lastModified: Date? = nil,
        explanation: String? = nil,
        isSelected: Bool = true
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.size = size
        self.category = category
        self.riskLevel = riskLevel
        self.lastModified = lastModified
        self.explanation = explanation
        self.isSelected = isSelected
    }

    public static func == (lhs: ScanItem, rhs: ScanItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public enum RiskLevel: String, Sendable, CaseIterable {
    case safe
    case cautionary
    case dangerous
}
