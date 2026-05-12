import SwiftUI
import MPCore
import MPUI
import MPScanners

struct UpdaterView: View {
    @State private var scanner = UpdaterScanner()
    var body: some View {
        InventoryModuleView(
            category: .updater,
            accent: MPColors.appsAccent,
            title: "Installed Apps",
            subtitle: "Inventory of apps in /Applications and ~/Applications with the version reported by their Info.plist. Auto-update wiring lands in a later release.",
            actionLabel: "Open",
            scanLabel: "Scan",
            scanner: scanner
        )
    }
}
