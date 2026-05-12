import SwiftUI

public enum MPTypography {
    public static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    public static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
    public static let title2 = Font.system(size: 18, weight: .semibold, design: .rounded)
    public static let headline = Font.system(size: 15, weight: .semibold)
    public static let body = Font.system(size: 13, weight: .regular)
    public static let callout = Font.system(size: 12, weight: .regular)
    public static let caption = Font.system(size: 11, weight: .medium)
    public static let captionSmall = Font.system(size: 10, weight: .regular)

    public static let monoBody = Font.system(size: 13, weight: .regular, design: .monospaced)
    public static let monoCaption = Font.system(size: 11, weight: .medium, design: .monospaced)

    public static let sidebarItem = Font.system(size: 13, weight: .medium)
    public static let sidebarSection = Font.system(size: 11, weight: .semibold)
    public static let statValue = Font.system(size: 36, weight: .bold, design: .rounded)
    public static let statLabel = Font.system(size: 11, weight: .medium)
}
