import SwiftUI
import MPCore

public enum MPColors {
    public static let sidebarBackground = Color(nsColor: .init(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
    public static let contentBackground = Color(nsColor: .init(red: 0.11, green: 0.11, blue: 0.14, alpha: 1.0))
    public static let cardBackground = Color(nsColor: .init(red: 0.14, green: 0.14, blue: 0.18, alpha: 1.0))
    public static let cardBorder = Color.white.opacity(0.06)
    public static let elevatedBackground = Color(nsColor: .init(red: 0.17, green: 0.17, blue: 0.21, alpha: 1.0))

    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.6)
    public static let textTertiary = Color.white.opacity(0.35)

    public static let cleanupAccent = Color(red: 0.30, green: 0.85, blue: 0.55)
    public static let filesAccent = Color(red: 0.35, green: 0.65, blue: 1.0)
    public static let appsAccent = Color(red: 0.90, green: 0.55, blue: 0.25)
    public static let speedAccent = Color(red: 1.0, green: 0.75, blue: 0.20)
    public static let protectionAccent = Color(red: 0.95, green: 0.35, blue: 0.40)
    public static let aiAccent = Color(red: 0.70, green: 0.45, blue: 1.0)

    public static let success = Color(red: 0.30, green: 0.85, blue: 0.55)
    public static let warning = Color(red: 1.0, green: 0.75, blue: 0.20)
    public static let danger = Color(red: 0.95, green: 0.35, blue: 0.40)

    public static let gradientCleanup = LinearGradient(
        colors: [cleanupAccent, Color(red: 0.20, green: 0.70, blue: 0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    public static let gradientFiles = LinearGradient(
        colors: [filesAccent, Color(red: 0.55, green: 0.40, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    public static let gradientProtection = LinearGradient(
        colors: [protectionAccent, Color(red: 1.0, green: 0.50, blue: 0.60)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    public static let gradientAI = LinearGradient(
        colors: [aiAccent, Color(red: 0.45, green: 0.60, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

public extension Color {
    static func accentForGroup(_ group: MPCore.ModuleGroup) -> Color {
        switch group {
        case .cleanup: return MPColors.cleanupAccent
        case .files: return MPColors.filesAccent
        case .apps: return MPColors.appsAccent
        case .speed: return MPColors.speedAccent
        case .protection: return MPColors.protectionAccent
        case .ai: return MPColors.aiAccent
        }
    }
}
