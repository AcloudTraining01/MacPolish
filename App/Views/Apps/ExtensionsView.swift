import SwiftUI
import MPCore
import MPUI
import MPScanners

struct ExtensionsView: View {
    @State private var scanner = ExtensionsScanner()
    var body: some View {
        InventoryModuleView(
            category: .extensions,
            accent: MPColors.appsAccent,
            title: "Extensions",
            subtitle: "Inventory of Spotlight importers, Quick Look generators, launch agents, and preference panes installed on this Mac.",
            actionLabel: "Reveal",
            scanLabel: "Scan",
            scanner: scanner
        )
    }
}
