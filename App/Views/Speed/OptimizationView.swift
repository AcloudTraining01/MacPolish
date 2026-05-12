import SwiftUI
import MPCore
import MPUI
import MPScanners

struct OptimizationView: View {
    @State private var scanner = OptimizationScanner()
    var body: some View {
        InventoryModuleView(
            category: .optimization,
            accent: MPColors.speedAccent,
            title: "Launch Items",
            subtitle: "Inventory of user and system launch agents/daemons that run at login or in the background.",
            actionLabel: "Reveal",
            scanLabel: "Scan",
            scanner: scanner
        )
    }
}
