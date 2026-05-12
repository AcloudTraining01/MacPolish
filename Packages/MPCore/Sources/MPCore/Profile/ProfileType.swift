import Foundation

public enum ProfileType: String, CaseIterable, Identifiable, Codable, Sendable {
    case developer = "Developer"
    case designer = "Designer"
    case student = "Student"
    case casual = "Casual"
    case powerUser = "Power User"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .developer:
            return "Xcode, Homebrew, Docker, and development tools"
        case .designer:
            return "Adobe Creative Suite, Figma, Sketch, and design assets"
        case .student:
            return "Documents, downloads, and email attachments"
        case .casual:
            return "Safe defaults with guided cleanup recommendations"
        case .powerUser:
            return "All modules enabled with expert-mode controls"
        }
    }

    public var systemImage: String {
        switch self {
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .designer: return "paintbrush"
        case .student: return "graduationcap"
        case .casual: return "person"
        case .powerUser: return "bolt"
        }
    }

    public var prioritizedCategories: [ScanCategory] {
        switch self {
        case .developer:
            return [.systemJunk, .largeOldFiles, .duplicateFinder, .optimization]
        case .designer:
            return [.systemJunk, .photoLibrary, .largeOldFiles, .duplicateFinder]
        case .student:
            return [.mailAttachments, .largeOldFiles, .trashBins, .privacy]
        case .casual:
            return [.smartScan, .systemJunk, .trashBins, .malwareRemoval]
        case .powerUser:
            return ScanCategory.allCases.filter { $0 != .assistant }
        }
    }
}
