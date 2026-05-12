import SwiftUI
import AppKit
import MPCore

public struct ReportExporter {

    public enum ExportFormat {
        case pdf
        case png
    }

    public static func export(
        results: [ScanResult],
        format: ExportFormat,
        to url: URL
    ) throws {
        let view = ReportView(results: results)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: estimateHeight(for: results))

        hostingView.layoutSubtreeIfNeeded()

        switch format {
        case .pdf:
            try exportPDF(view: hostingView, to: url)
        case .png:
            try exportPNG(view: hostingView, to: url)
        }
    }

    private static func exportPDF(view: NSView, to url: URL) throws {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: view.bounds.width, height: view.bounds.height + 60)
        printInfo.topMargin = 30
        printInfo.bottomMargin = 30
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.isHorizontallyCentered = true

        let data = view.dataWithPDF(inside: view.bounds)
        try data.write(to: url, options: .atomic)
    }

    private static func exportPNG(view: NSView, to url: URL) throws {
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ExportError.renderFailed
        }
        view.cacheDisplay(in: view.bounds, to: bitmapRep)

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw ExportError.encodingFailed
        }
        try pngData.write(to: url, options: .atomic)
    }

    private static func estimateHeight(for results: [ScanResult]) -> CGFloat {
        let headerHeight: CGFloat = 120
        let categoryHeight: CGFloat = 60
        let itemHeight: CGFloat = 24
        let footerHeight: CGFloat = 60

        var total = headerHeight + footerHeight
        for result in results {
            total += categoryHeight
            total += CGFloat(min(result.items.count, 20)) * itemHeight
        }
        return max(total, 400)
    }

    public enum ExportError: LocalizedError {
        case renderFailed
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .renderFailed: return "Failed to render the report view."
            case .encodingFailed: return "Failed to encode the image data."
            }
        }
    }
}

struct ReportView: View {
    let results: [ScanResult]

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            Divider()

            ForEach(results, id: \.category) { result in
                categorySection(result)
            }

            Spacer(minLength: 8)
            footerSection
        }
        .padding(24)
        .frame(width: 800)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                Text("MacPolish Scan Report")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
            }

            Text("Generated on \(dateFormatter.string(from: Date()))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                statBadge(
                    label: "Total Items",
                    value: "\(results.reduce(0) { $0 + $1.items.count })"
                )
                statBadge(
                    label: "Recoverable Space",
                    value: SizeFormatter.format(results.reduce(0) { $0 + $1.totalSize })
                )
                statBadge(
                    label: "Categories Scanned",
                    value: "\(results.count)"
                )
            }
        }
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private func categorySection(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.category.systemImage)
                    .foregroundStyle(.blue)
                Text(result.category.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(result.items.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(SizeFormatter.format(result.totalSize))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }

            let displayItems = Array(result.items.prefix(20))
            ForEach(displayItems) { item in
                HStack {
                    Circle()
                        .fill(colorForRisk(item.riskLevel))
                        .frame(width: 6, height: 6)
                    Text(item.name)
                        .font(.system(size: 10))
                        .lineLimit(1)
                    Spacer()
                    Text(SizeFormatter.format(item.size))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if result.items.count > 20 {
                Text("... and \(result.items.count - 20) more items")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func colorForRisk(_ risk: RiskLevel) -> Color {
        switch risk {
        case .safe: return .green
        case .cautionary: return .orange
        case .dangerous: return .red
        }
    }

    private var footerSection: some View {
        HStack {
            Text("MacPolish v0.2.0")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("macpolish.app")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}
