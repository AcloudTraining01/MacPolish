import SwiftUI
import MPCore
import MPUI
import MPScanners

struct PrivacyView: View {
    @State private var scanner = PrivacyScanner()
    var body: some View {
        InventoryModuleView(
            category: .privacy,
            accent: MPColors.protectionAccent,
            title: "Privacy",
            subtitle: "Browser history files and Quick Look thumbnail caches. Items marked .cautionary belong to a running process — close the app first.",
            actionLabel: "Clean",
            scanLabel: "Scan",
            scanner: scanner
        )
    }
}
