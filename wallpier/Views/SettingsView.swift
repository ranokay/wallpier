//
//  SettingsView.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case behavior = "Behavior"
        case display = "Display"
        case system = "System"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .behavior: return "timer"
            case .display: return "display"
            case .system: return "macwindow"
            case .advanced: return "cpu"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // Settings Sidebar
            List(SettingsTab.allCases, id: \.rawValue, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)

        } detail: {
            // Settings Content
            ScrollView {
                VStack(spacing: 0) {
                    // Content based on selected tab
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(viewModel: viewModel)
                    case .behavior:
                        BehaviorSettingsView(viewModel: viewModel)
                    case .display:
                        DisplaySettingsView(viewModel: viewModel)
                    case .system:
                        SystemSettingsView(viewModel: viewModel)
                    case .advanced:
                        AdvancedSettingsView(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    viewModel.cancelChanges()
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.saveSettings()
                    dismiss()
                }
                .disabled(!viewModel.canSave)
            }
        }
        .alert("Validation Errors", isPresented: .constant(!viewModel.validationErrors.isEmpty)) {
            Button("OK") { }
        } message: {
            VStack(alignment: .leading) {
                ForEach(viewModel.validationErrors, id: \.self) { error in
                    Text("• \(error)")
                }
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Folder Selection
            GroupBox("Image Folder") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected Folder")
                                .font(.headline)
                            Text(viewModel.folderDisplayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Choose...") {
                            viewModel.selectFolder()
                        }
                    }

                    if let folderPath = viewModel.settings.folderPath {
                        Text(folderPath.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    Toggle("Scan subfolders recursively", isOn: $viewModel.settings.isRecursiveScanEnabled)
                        .help("Include images from subfolders when scanning")

                    // Folder validation
                    let validation = viewModel.validateFolderPath()
                    HStack {
                        Image(systemName: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(validation.isValid ? .green : .orange)
                        Text(validation.info)
                            .font(.caption)
                    }
                }
            }

            // App Behavior
            GroupBox("Application") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch at startup", isOn: $viewModel.settings.launchAtStartup)
                        .help("Automatically start Wallpier when you log in")

                    Toggle("Show menu bar icon", isOn: $viewModel.settings.showMenuBarIcon)
                        .help("Display a menu bar icon for quick access")

                    Toggle("Show notifications", isOn: $viewModel.settings.showNotifications)
                        .help("Display notifications when wallpaper changes")
                }
            }

            // Status Message
            if !viewModel.statusMessage.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            Spacer()
        }
    }
}

// MARK: - Behavior Settings

struct BehaviorSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Cycling Configuration
            GroupBox("Cycling Behavior") {
                VStack(alignment: .leading, spacing: 16) {
                    // Cycling interval
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Change wallpaper every:")
                            .font(.headline)

                        Picker("Interval", selection: $viewModel.settings.cyclingInterval) {
                            ForEach(viewModel.availableIntervals, id: \.seconds) { interval in
                                Text(interval.name).tag(interval.seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200, alignment: .leading)

                        Text("Current: \(viewModel.currentIntervalName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Sort and shuffle
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image Order")
                            .font(.headline)

                        Picker("Sort Order", selection: $viewModel.settings.sortOrder) {
                            ForEach(ImageSortOrder.allCases, id: \.self) { order in
                                Text(order.displayName).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200, alignment: .leading)

                        Toggle("Shuffle images", isOn: $viewModel.settings.isShuffleEnabled)
                            .help("Randomize the order of images")
                    }
                }
            }

            // Power Management
            GroupBox("Power Management") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Pause cycling on battery power", isOn: $viewModel.settings.advancedSettings.pauseOnBattery)
                        .help("Stop changing wallpapers when running on battery to save power")

                    Toggle("Pause cycling in low power mode", isOn: $viewModel.settings.advancedSettings.pauseInLowPowerMode)
                        .help("Stop changing wallpapers when macOS low power mode is enabled")
                }
            }

            Spacer()
        }
    }
}

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Wallpaper Display
            GroupBox("Wallpaper Display") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scaling Mode")
                            .font(.headline)

                        Picker("Scaling", selection: $viewModel.settings.scalingMode) {
                            ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200, alignment: .leading)

                        Text(scalingModeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Multi-Monitor Settings
            GroupBox("Multi-Monitor Setup") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use same wallpaper on all monitors",
                           isOn: $viewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors)
                        .help("Apply the same wallpaper to all connected displays")

                    // Monitor count info
                    let screenCount = NSScreen.screens.count
                    HStack {
                        Image(systemName: "display")
                            .foregroundColor(.secondary)
                        Text("\(screenCount) monitor(s) detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // File Filters
            GroupBox("File Types") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Supported Image Types")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("HEIC files", isOn: $viewModel.settings.fileFilters.includeHEICFiles)
                        Toggle("GIF files", isOn: $viewModel.settings.fileFilters.includeGIFFiles)
                        Toggle("WebP files", isOn: $viewModel.settings.fileFilters.includeWebPFiles)
                    }

                    Text("Always included: JPEG, PNG, BMP, TIFF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var scalingModeDescription: String {
        switch viewModel.settings.scalingMode {
        case .fill:
            return "Scale image to fill screen, cropping if necessary"
        case .fit:
            return "Scale image to fit within screen, maintaining aspect ratio"
        case .stretch:
            return "Stretch image to fill entire screen"
        case .center:
            return "Center image without scaling"
        case .tile:
            return "Tile image across screen"
        }
    }
}

// MARK: - System Settings

struct SystemSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var systemService: SystemService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // App Startup & Integration
            GroupBox("System Integration") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Startup")
                                    .font(.headline)
                                Text("Start Wallpier when you log in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { systemService.isLaunchAtStartupEnabled },
                                set: { enabled in
                                    Task { let _ = await systemService.setLaunchAtStartup(enabled) }
                                    viewModel.settings.systemIntegration?.launchAtStartup = enabled
                                }
                            ))
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Menu Bar Only Mode")
                                    .font(.headline)
                                Text("Hide dock icon, keep only menu bar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { viewModel.settings.systemIntegration?.hideDockIcon ?? false },
                                set: { enabled in
                                    systemService.configureDockVisibility(!enabled)
                                    viewModel.settings.systemIntegration?.hideDockIcon = enabled
                                }
                            ))
                        }

                        if systemService.isDockHidden {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("Restart required for dock icon changes to take full effect")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }
            }

            // Notifications & Status
            GroupBox("Notifications") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show wallpaper change notifications",
                           isOn: Binding(
                               get: { viewModel.settings.systemIntegration?.showWallpaperChangeNotifications ?? false },
                               set: { viewModel.settings.systemIntegration?.showWallpaperChangeNotifications = $0 }
                           ))
                        .help("Display a notification when the wallpaper changes")
                }
            }

            // Power & Performance
            GroupBox("Power Management") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Pause when screen is locked",
                           isOn: Binding(
                               get: { viewModel.settings.systemIntegration?.pauseWhenScreenLocked ?? false },
                               set: { viewModel.settings.systemIntegration?.pauseWhenScreenLocked = $0 }
                           ))
                        .help("Stop cycling wallpapers when the screen is locked")

                    Toggle("Pause during presentations",
                           isOn: Binding(
                               get: { viewModel.settings.systemIntegration?.pauseDuringPresentations ?? true },
                               set: { viewModel.settings.systemIntegration?.pauseDuringPresentations = $0 }
                           ))
                        .help("Pause cycling when fullscreen apps or presentations are active")

                    Toggle("Pause on battery power", isOn: $viewModel.settings.advancedSettings.pauseOnBattery)
                        .help("Stop cycling to conserve battery when not plugged in")

                    Toggle("Pause in low power mode", isOn: $viewModel.settings.advancedSettings.pauseInLowPowerMode)
                        .help("Stop cycling when macOS low power mode is enabled")
                }
            }

            // Permissions & Status
            GroupBox("Permissions & Status") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("File System Access")
                                .font(.headline)

                            HStack {
                                Circle()
                                    .fill(systemService.permissionStatus.isFullyGranted ? .green : .orange)
                                    .frame(width: 8, height: 8)

                                Text(permissionStatusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("Wallpier only accesses folders you explicitly select")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .opacity(0.8)
                        }

                        Spacer()

                        Button("Select Folder") {
                            Task {
                                let granted = await systemService.requestPermissions()
                                if granted {
                                    // Optionally update the main settings folder path too
                                    // This is handled by the folder selection in the permission request
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    // System Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Information")
                            .font(.headline)

                        let systemInfo = systemService.getSystemInfo()

                        HStack {
                            Text("macOS:")
                            Spacer()
                            Text(systemInfo["macOSVersion"] as? String ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)

                        HStack {
                            Text("App Version:")
                            Spacer()
                            Text(systemInfo["appVersion"] as? String ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)

                        HStack {
                            Text("App State:")
                            Spacer()
                            Text(systemInfo["appState"] as? String ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }

            Spacer()
        }
    }

    private var permissionStatusText: String {
        switch systemService.permissionStatus {
        case .granted:
            return "Ready to access selected folders"
        case .denied:
            return "No folder access granted"
        case .notDetermined:
            return "Folder access not configured"
        case .partiallyGranted(_, _):
            return "Limited folder access"
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Performance Settings
            GroupBox("Performance") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Image Cache")
                            .font(.headline)

                        HStack {
                            Text("Maximum cache size:")
                            Spacer()
                            TextField("MB", value: $viewModel.settings.advancedSettings.maxCacheSizeMB, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("MB")
                        }

                        HStack {
                            Text("Maximum cached images:")
                            Spacer()
                            TextField("Count", value: $viewModel.settings.advancedSettings.maxCachedImages, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }

                        Toggle("Preload next image", isOn: $viewModel.settings.advancedSettings.preloadNextImage)
                            .help("Load the next image in background for smoother transitions")
                    }
                }
            }

            // File Size Filters
            GroupBox("File Size Limits") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Minimum file size:")
                        Spacer()
                        TextField("Bytes", value: $viewModel.settings.fileFilters.minimumFileSize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("bytes (0 = no limit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Maximum file size:")
                        Spacer()
                        TextField("Bytes", value: $viewModel.settings.fileFilters.maximumFileSize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("bytes (0 = no limit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Debugging
            GroupBox("Debugging") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable detailed logging", isOn: $viewModel.settings.advancedSettings.enableDetailedLogging)
                        .help("Log detailed information for troubleshooting")

                    if viewModel.settings.advancedSettings.enableDetailedLogging {
                        Text("⚠️ Detailed logging may impact performance")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            // System Recommendations
            if !viewModel.getSystemRecommendations().isEmpty {
                GroupBox("Recommendations") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.getSystemRecommendations(), id: \.self) { recommendation in
                            HStack(alignment: .top) {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                                Text(recommendation)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    viewModel.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(settings: WallpaperSettings()))
}
