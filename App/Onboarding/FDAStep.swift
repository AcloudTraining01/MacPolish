import SwiftUI
import MPUI

struct FDAStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    @State private var hasAccess = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: hasAccess ? "checkmark.shield" : "lock.shield")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(hasAccess ? MPColors.success : MPColors.protectionAccent.opacity(0.7))
                .symbolEffect(.pulse.byLayer, options: .repeating, isActive: !hasAccess)

            VStack(spacing: 12) {
                Text(hasAccess ? "Access Granted" : "Full Disk Access")
                    .font(MPTypography.title)
                    .foregroundStyle(MPColors.textPrimary)

                Text(hasAccess ? "MacPolish now has access to scan all required locations." : "MacPolish needs Full Disk Access to scan caches,\nlogs, and system junk across your Mac.")
                    .font(MPTypography.body)
                    .foregroundStyle(MPColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            if !hasAccess {
                VStack(spacing: 12) {
                    instructionRow(number: 1, text: "Click \"Open System Settings\" below")
                    instructionRow(number: 2, text: "Find MacPolish in the list")
                    instructionRow(number: 3, text: "Toggle it ON")
                }
                .padding(.horizontal, 60)
            }

            HStack(spacing: 16) {
                if !hasAccess {
                    MPButton("Open System Settings", icon: "gear", style: .primary(MPColors.protectionAccent)) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    MPButton("Continue", icon: "arrow.right", style: .primary(MPColors.success)) {
                        onNext()
                    }
                }
            }

            Spacer()

            if !hasAccess {
                Button("Skip for now") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .font(MPTypography.caption)
                .foregroundStyle(MPColors.textTertiary)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            checkFDA()
        }
        .onAppear {
            checkFDA()
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(MPColors.protectionAccent)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(MPColors.protectionAccent.opacity(0.15))
                )

            Text(text)
                .font(MPTypography.body)
                .foregroundStyle(MPColors.textSecondary)

            Spacer()
        }
    }
    
    private func checkFDA() {
        // TCC.db read test is the standard way to check for FDA
        let path = "/Library/Application Support/com.apple.TCC/TCC.db"
        let handle = FileHandle(forReadingAtPath: path)
        if handle != nil {
            hasAccess = true
            handle?.closeFile()
        } else {
            hasAccess = false
        }
    }
}
