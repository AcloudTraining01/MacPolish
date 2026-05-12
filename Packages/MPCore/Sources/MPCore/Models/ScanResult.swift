import Foundation

public struct ScanResult: Sendable {
    public let category: ScanCategory
    public let items: [ScanItem]
    public let totalSize: Int64
    public let scanDuration: TimeInterval
    public let timestamp: Date

    public init(
        category: ScanCategory,
        items: [ScanItem],
        totalSize: Int64,
        scanDuration: TimeInterval,
        timestamp: Date = .now
    ) {
        self.category = category
        self.items = items
        self.totalSize = totalSize
        self.scanDuration = scanDuration
        self.timestamp = timestamp
    }

    public var selectedSize: Int64 {
        items.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    public var selectedCount: Int {
        items.filter(\.isSelected).count
    }
}

public struct ScanProgress: Sendable {
    public let category: ScanCategory
    public let phase: Phase
    public let currentPath: String?
    public let itemsFound: Int
    public let bytesFound: Int64

    public enum Phase: Sendable, Equatable {
        case idle
        case preparing
        case scanning
        case analyzing
        case complete
        case failed(String)

        public static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing),
                 (.scanning, .scanning), (.analyzing, .analyzing),
                 (.complete, .complete): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }

        public var description: String {
            switch self {
            case .idle: return "Ready"
            case .preparing: return "Preparing..."
            case .scanning: return "Scanning..."
            case .analyzing: return "Analyzing..."
            case .complete: return "Complete"
            case .failed(let msg): return "Failed: \(msg)"
            }
        }
    }

    public init(
        category: ScanCategory,
        phase: Phase,
        currentPath: String? = nil,
        itemsFound: Int = 0,
        bytesFound: Int64 = 0
    ) {
        self.category = category
        self.phase = phase
        self.currentPath = currentPath
        self.itemsFound = itemsFound
        self.bytesFound = bytesFound
    }
}

public typealias ScanPhase = ScanProgress.Phase
