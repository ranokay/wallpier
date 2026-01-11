//
//  GeneralSettingsView.swift
//  wallpier
//
//  General settings tab - Application behavior and power management
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var appVisibilityMode: String {
        let isDockHidden = viewModel.settings.systemIntegration.hideDockIcon
        let showsMenuBar = viewModel.settings.showMenuBarIcon

        if showsMenuBar && !isDockHidden {
            return "Dock + Menu Bar"
        } else if showsMenuBar && isDockHidden {
            return "Menu Bar Only"
        } else if !showsMenuBar && !isDockHidden {
            return "Dock Only"
        } else {
            return "Hidden (Not Recommended)"
        }
    }

    var body: some View {
        Form {
            Section("Application Behavior") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.systemIntegration.launchAtStartup },
                    set: { enabled in
                        Task {
                            let _ = await SystemService().setLaunchAtStartup(enabled)
                            viewModel.settings.systemIntegration.launchAtStartup = enabled
                        }
                    }
                )) {
                    Text("Launch at startup")
                    Text("Automatically start Wallpier when you log in")
                        .captionStyle()
                }
                .accessibilityLabel("Launch at startup")
                .accessibilityHint("Automatically start Wallpier when you log in")

                Toggle(isOn: $viewModel.settings.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("Display a menu bar icon for quick access")
                        .captionStyle()
                }
                .accessibilityLabel("Show menu bar icon")
                .accessibilityHint("Display a menu bar icon for quick access")

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.systemIntegration.hideDockIcon },
                        set: { enabled in
                            SystemService().configureDockVisibility(!enabled)
                            viewModel.settings.systemIntegration.hideDockIcon = enabled
                        }
                    )) {
                        Text("Hide dock icon")
                        Text("Remove app from dock (menu bar only mode)")
                            .captionStyle()
                    }

                    if viewModel.settings.systemIntegration.hideDockIcon {
                        Text("Restart required for dock changes to take full effect")
                            .captionStyle()
                            .foregroundColor(AppColors.info)
                    }
                }
            }

            Section("Power Management") {
                Toggle("Pause cycling on battery power", isOn: $viewModel.settings.advancedSettings.pauseOnBattery)
                    .accessibilityLabel("Pause on battery")
                    .accessibilityHint("Stop wallpaper cycling when running on battery power")
                Toggle("Pause cycling in low power mode", isOn: $viewModel.settings.advancedSettings.pauseInLowPowerMode)
                    .accessibilityLabel("Pause in low power mode")
                    .accessibilityHint("Stop wallpaper cycling when low power mode is enabled")
            }

            if !viewModel.statusMessage.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppColors.info)
                        Text(viewModel.statusMessage)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
