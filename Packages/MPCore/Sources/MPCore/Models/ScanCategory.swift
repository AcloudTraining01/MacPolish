import Foundation

public enum ScanCategory: String, CaseIterable, Identifiable, Sendable {
    case systemJunk = "System Junk"
    case mailAttachments = "Mail Attachments"
    case trashBins = "Trash Bins"
    case timeMachine = "Time Machine Snapshots"
    case spaceLens = "Space Lens"
    case largeOldFiles = "Large & Old Files"
    case duplicateFinder = "Duplicate Finder"
    case photoLibrary = "Photo Library"
    case shredder = "Shredder"
    case uninstaller = "Uninstaller"
    case updater = "Updater"
    case extensions = "Extensions"
    case optimization = "Optimization"
    case maintenance = "Maintenance"
    case systemMonitor = "System Monitor"
    case batteryHealth = "Battery Health"
    case malwareRemoval = "Malware Removal"
    case privacy = "Privacy"
    case smartScan = "Smart Scan"
    case assistant = "AI Assistant"

    public var id: String { rawValue }

    public var group: ModuleGroup {
        switch self {
        case .systemJunk, .mailAttachments, .trashBins, .timeMachine:
            return .cleanup
        case .spaceLens, .largeOldFiles, .duplicateFinder, .photoLibrary, .shredder:
            return .files
        case .uninstaller, .updater, .extensions:
            return .apps
        case .optimization, .maintenance, .systemMonitor, .batteryHealth:
            return .speed
        case .malwareRemoval, .privacy:
            return .protection
        case .smartScan, .assistant:
            return .ai
        }
    }

    public var systemImage: String {
        switch self {
        case .systemJunk: return "trash.circle"
        case .mailAttachments: return "paperclip"
        case .trashBins: return "trash"
        case .timeMachine: return "clock.arrow.circlepath"
        case .spaceLens: return "chart.pie"
        case .largeOldFiles: return "doc.badge.clock"
        case .duplicateFinder: return "doc.on.doc"
        case .photoLibrary: return "photo.on.rectangle"
        case .shredder: return "scissors"
        case .uninstaller: return "xmark.app"
        case .updater: return "arrow.triangle.2.circlepath"
        case .extensions: return "puzzlepiece.extension"
        case .optimization: return "gauge.with.dots.needle.67percent"
        case .maintenance: return "wrench.and.screwdriver"
        case .systemMonitor: return "chart.xyaxis.line"
        case .batteryHealth: return "battery.75percent"
        case .malwareRemoval: return "shield.checkered"
        case .privacy: return "hand.raised"
        case .smartScan: return "sparkle.magnifyingglass"
        case .assistant: return "bubble.left.and.text.bubble.right"
        }
    }

    public var accentColorName: String {
        switch group {
        case .cleanup: return "CleanupAccent"
        case .files: return "FilesAccent"
        case .apps: return "AppsAccent"
        case .speed: return "SpeedAccent"
        case .protection: return "ProtectionAccent"
        case .ai: return "AIAccent"
        }
    }
}

public enum ModuleGroup: String, CaseIterable, Identifiable, Sendable {
    case cleanup = "Cleanup"
    case files = "Files"
    case apps = "Applications"
    case speed = "Speed"
    case protection = "Protection"
    case ai = "AI"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .cleanup: return "bubbles.and.sparkles"
        case .files: return "folder"
        case .apps: return "app.badge.checkmark"
        case .speed: return "gauge.with.dots.needle.bottom.50percent"
        case .protection: return "shield.lefthalf.filled"
        case .ai: return "brain.head.profile"
        }
    }

    public var categories: [ScanCategory] {
        ScanCategory.allCases.filter { $0.group == self }
    }
}
