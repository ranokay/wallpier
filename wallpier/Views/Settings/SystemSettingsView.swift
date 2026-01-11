//
//  SystemSettingsView.swift
//  wallpier
//
//  System settings tab - System behavior and permissions
//

import SwiftUI

struct SystemSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var systemService: SystemService

    var body: some View {
        Form {
            Section("System Behavior") {
                Toggle("Pause when screen is locked", isOn: Binding(
                    get: { viewModel.settings.systemIntegration.pauseWhenScreenLocked },
                    set: { viewModel.settings.systemIntegration.pauseWhenScreenLocked = $0 }
                ))
                Toggle("Pause during presentations", isOn: Binding(
                    get: { viewModel.settings.systemIntegration.pauseDuringPresentations },
                    set: { viewModel.settings.systemIntegration.pauseDuringPresentations = $0 }
                ))
            }

            Section("Permissions & Status") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("File System Access")
                        Spacer()
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundColor(systemService.permissionStatus.isFullyGranted ? AppColors.success : AppColors.warning)
                        Text(permissionStatusText)
                            .captionStyle()
                    }
                    Text("Wallpier only accesses folders you explicitly select")
                        .font(Typography.caption2)
                        .foregroundColor(AppColors.contentSecondary)

                    Button("Select Folder") {
                        Task {
                            let _ = await systemService.requestPermissions()
                        }
                    }
                }

                let systemInfo = systemService.getSystemInfo()
                LabeledContent("macOS", value: systemInfo["macOSVersion"] as? String ?? "Unknown")
                LabeledContent("App Version", value: systemInfo["appVersion"] as? String ?? "Unknown")
                LabeledContent("App State", value: systemInfo["appState"] as? String ?? "Unknown")
            }
        }
        .formStyle(.grouped)
    }

    private var permissionStatusText: String {
        switch systemService.permissionStatus {
        case .granted: return "Ready to access selected folders"
        case .denied: return "No folder access granted"
        case .notDetermined: return "Folder access not configured"
        case .partiallyGranted(_, _): return "Limited folder access"
        }
    }
}
