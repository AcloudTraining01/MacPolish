import SwiftUI
import MPUI
import ServiceManagement
import os.log

struct HelperStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    @State private var isInstalling = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(MPColors.speedAccent.opacity(0.7))
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: 12) {
                Text("Install Helper Tool")
                    .font(MPTypography.title)
                    .foregroundStyle(MPColors.textPrimary)

                Text("Some cleanup tasks need elevated privileges.\nThe helper runs securely in the background.")
                    .font(MPTypography.body)
                    .foregroundStyle(MPColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "trash.circle", text: "Delete protected cache files")
                featureRow(icon: "wrench", text: "Run maintenance scripts")
                featureRow(icon: "network", text: "Flush DNS and rebuild indexes")
            }
            .padding(.horizontal, 80)
            
            if let errorMsg = errorMsg {
                Text(errorMsg)
                    .font(MPTypography.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    MPButton("Install Helper", icon: "arrow.down.circle", style: .primary(MPColors.speedAccent)) {
                        installHelper()
                    }
                }
            }

            Spacer()

            Button("Skip for now") {
                onSkip()
            }
            .buttonStyle(.plain)
            .font(MPTypography.caption)
            .foregroundStyle(MPColors.textTertiary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(MPColors.speedAccent)
                .frame(width: 24)

            Text(text)
                .font(MPTypography.body)
                .foregroundStyle(MPColors.textSecondary)

            Spacer()
        }
    }
    
    private func installHelper() {
        isInstalling = true
        errorMsg = nil
        
        Task {
            do {
                let service = SMAppService.daemon(plistName: "com.macpolish.helper.plist")
                
                if service.status == .enabled {
                    // Already installed
                    await MainActor.run { onNext() }
                    return
                }
                
                try service.register()
                
                await MainActor.run {
                    isInstalling = false
                    onNext()
                }
            } catch {
                os_log("Failed to register helper tool: %{public}@", error.localizedDescription)
                await MainActor.run {
                    self.errorMsg = "Installation failed. You can skip this and try again later in Settings."
                    self.isInstalling = false
                }
            }
        }
    }
}
