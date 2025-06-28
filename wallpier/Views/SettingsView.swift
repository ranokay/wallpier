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
        HStack(spacing: 0) {
            // Settings Sidebar
            VStack(spacing: 0) {
                // Sidebar Header
                VStack(spacing: 8) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Sidebar Content
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                            Button(action: { selectedTab = tab }) {
                                HStack(spacing: 12) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(selectedTab == tab ? .white : .primary)
                                        .frame(width: 20)

                                    Text(tab.rawValue)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(selectedTab == tab ? .white : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 12)
                }

                Spacer()

                // Footer with save/cancel buttons
                VStack(spacing: 8) {
                    Divider()

                    VStack(spacing: 8) {
                        Button("Save") {
                            viewModel.saveSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(viewModel.isSaving || !viewModel.hasUnsavedChanges || !viewModel.validationErrors.isEmpty)

                        Button("Cancel") {
                            viewModel.cancelChanges()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(width: 200)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Settings Content
            VStack(spacing: 0) {
                // Content Header
                VStack(spacing: 8) {
                    HStack {
                        Label(selectedTab.rawValue, systemImage: selectedTab.icon)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        // Status indicator if there are validation errors
                        if !viewModel.validationErrors.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .help("Settings have validation errors")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Scrollable Content
                ScrollView(.vertical, showsIndicators: true) {
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
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 750, height: 550) // Fixed dimensions
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            // Toast notification overlay
            ToastView(
                isPresented: $viewModel.showToast,
                message: viewModel.toastMessage
            )
        )
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

    private var appVisibilityMode: String {
        let isDockHidden = viewModel.settings.systemIntegration?.hideDockIcon ?? false
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
        VStack(alignment: .leading, spacing: 32) {
            // Folder Selection
            SettingsGroup(title: "Image Folder", icon: "folder") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected Folder")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(viewModel.folderDisplayName)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button("Choose...") {
                            viewModel.selectFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if let folderPath = viewModel.settings.folderPath {
                        Text(folderPath.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }

                    Toggle("Scan subfolders recursively", isOn: $viewModel.settings.isRecursiveScanEnabled)
                        .help("Include images from subfolders when scanning")
                        .toggleStyle(SwitchToggleStyle())

                    // Folder validation
                    let validation = viewModel.validateFolderPath()
                    HStack(spacing: 8) {
                        Image(systemName: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(validation.isValid ? .green : .orange)
                            .font(.system(size: 14))
                        Text(validation.info)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(validation.isValid ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    )
                }
            }

            // App Behavior
            SettingsGroup(title: "Application Behavior", icon: "app.badge") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsToggleRow(
                        title: "Launch at startup",
                        description: "Automatically start Wallpier when you log in",
                        isOn: Binding(
                            get: { viewModel.settings.systemIntegration?.launchAtStartup ?? false },
                            set: { enabled in
                                Task {
                                    let _ = await SystemService().setLaunchAtStartup(enabled)
                                    viewModel.settings.systemIntegration?.launchAtStartup = enabled
                                }
                            }
                        )
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("App Visibility")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 8) {
                            let isDockHidden = viewModel.settings.systemIntegration?.hideDockIcon ?? false

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Current mode:")
                                        .font(.caption)
                                    Text(appVisibilityMode)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                                                        SettingsToggleRow(
                                title: "Show menu bar icon",
                                description: "Display a menu bar icon for quick access",
                                isOn: $viewModel.settings.showMenuBarIcon
                            )

                            SettingsToggleRow(
                                title: "Hide dock icon",
                                description: "Remove app from dock (menu bar only mode)",
                                isOn: Binding(
                                    get: { viewModel.settings.systemIntegration?.hideDockIcon ?? false },
                                    set: { enabled in
                                        SystemService().configureDockVisibility(!enabled)
                                        viewModel.settings.systemIntegration?.hideDockIcon = enabled
                                    }
                                )
                            )

                            if isDockHidden {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                    Text("Restart required for dock changes to take full effect")
                                        .font(.caption2)
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
            }

            // Status Message
            if !viewModel.statusMessage.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }

            Spacer(minLength: 20)
        }
    }
}

// MARK: - Behavior Settings

struct BehaviorSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Cycling Configuration
            SettingsGroup(title: "Cycling Behavior", icon: "arrow.clockwise") {
                VStack(alignment: .leading, spacing: 20) {
                    // Cycling interval
                    SettingsPickerRow(
                        title: "Change wallpaper every:",
                        description: "How often to automatically change the wallpaper",
                        selection: $viewModel.settings.cyclingInterval,
                        options: viewModel.availableIntervals.map { (value: $0.seconds, label: $0.name) }
                    )

                    Divider()
                        .padding(.vertical, 4)

                    // Sort and shuffle
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsPickerRow(
                            title: "Image order",
                            description: "How to sort images in the cycling queue",
                            selection: $viewModel.settings.sortOrder,
                            options: ImageSortOrder.allCases.map { (value: $0, label: $0.displayName) }
                        )

                        SettingsToggleRow(
                            title: "Shuffle images",
                            description: "Randomize the order of images",
                            isOn: $viewModel.settings.isShuffleEnabled
                        )
                    }
                }
            }

            // Power Management
            SettingsGroup(title: "Power Management", icon: "battery.100") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsToggleRow(
                        title: "Pause cycling on battery power",
                        description: "Stop changing wallpapers when running on battery to save power",
                        isOn: $viewModel.settings.advancedSettings.pauseOnBattery
                    )

                    SettingsToggleRow(
                        title: "Pause cycling in low power mode",
                        description: "Stop changing wallpapers when macOS low power mode is enabled",
                        isOn: $viewModel.settings.advancedSettings.pauseInLowPowerMode
                    )
                }
            }

            Spacer(minLength: 20)
        }
    }
}

// MARK: - Display Settings

struct DisplaySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Wallpaper Display
            SettingsGroup(title: "Wallpaper Display", icon: "photo.on.rectangle") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsPickerRow(
                        title: "Scaling Mode",
                        description: scalingModeDescription,
                        selection: $viewModel.settings.scalingMode,
                        options: WallpaperScalingMode.allCases.map { (value: $0, label: $0.displayName) }
                    )
                }
            }

            // Multi-Monitor Settings
            SettingsGroup(title: "Multi-Monitor Setup", icon: "rectangle.3.group") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsToggleRow(
                        title: "Use same wallpaper on all monitors",
                        description: "Apply the same wallpaper to all connected displays",
                        isOn: $viewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors
                    )

                    // Monitor count info
                    let screenCount = NSScreen.screens.count
                    HStack(spacing: 8) {
                        Image(systemName: "display")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 14))
                        Text("\(screenCount) monitor(s) detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                }
            }

            // File Filters
            SettingsGroup(title: "Supported File Types", icon: "doc.on.doc") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsToggleRow(
                            title: "HEIC files",
                            description: "High Efficiency Image Format (iOS/macOS photos)",
                            isOn: $viewModel.settings.fileFilters.includeHEICFiles
                        )

                        SettingsToggleRow(
                            title: "GIF files",
                            description: "Animated and static GIF images",
                            isOn: $viewModel.settings.fileFilters.includeGIFFiles
                        )

                        SettingsToggleRow(
                            title: "WebP files",
                            description: "Modern web image format",
                            isOn: $viewModel.settings.fileFilters.includeWebPFiles
                        )
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("Always included: JPEG, PNG, BMP, TIFF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                }
            }

            Spacer(minLength: 20)
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
        VStack(alignment: .leading, spacing: 32) {


            // System Behavior
            SettingsGroup(title: "System Behavior", icon: "bolt.circle") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsToggleRow(
                        title: "Pause when screen is locked",
                        description: "Stop cycling wallpapers when the screen is locked",
                        isOn: Binding(
                            get: { viewModel.settings.systemIntegration?.pauseWhenScreenLocked ?? false },
                            set: { viewModel.settings.systemIntegration?.pauseWhenScreenLocked = $0 }
                        )
                    )

                    SettingsToggleRow(
                        title: "Pause during presentations",
                        description: "Pause cycling when fullscreen apps or presentations are active",
                        isOn: Binding(
                            get: { viewModel.settings.systemIntegration?.pauseDuringPresentations ?? true },
                            set: { viewModel.settings.systemIntegration?.pauseDuringPresentations = $0 }
                        )
                    )
                }
            }

            // Permissions & Status
            SettingsGroup(title: "Permissions & Status", icon: "lock.shield") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("File System Access")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack(spacing: 8) {
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
                        .controlSize(.large)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // System Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("System Information")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        let systemInfo = systemService.getSystemInfo()

                        VStack(spacing: 6) {
                            SystemInfoRow(
                                label: "macOS:",
                                value: systemInfo["macOSVersion"] as? String ?? "Unknown"
                            )

                            SystemInfoRow(
                                label: "App Version:",
                                value: systemInfo["appVersion"] as? String ?? "Unknown"
                            )

                            SystemInfoRow(
                                label: "App State:",
                                value: systemInfo["appState"] as? String ?? "Unknown"
                            )
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }

            Spacer(minLength: 20)
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

struct SystemInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Performance Settings
            SettingsGroup(title: "Performance", icon: "speedometer") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image Cache")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        VStack(spacing: 12) {
                            HStack {
                                Text("Maximum cache size:")
                                    .font(.caption)
                                Spacer()
                                HStack(spacing: 4) {
                                    TextField("MB", value: $viewModel.settings.advancedSettings.maxCacheSizeMB, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("MB")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Text("Maximum cached images:")
                                    .font(.caption)
                                Spacer()
                                TextField("Count", value: $viewModel.settings.advancedSettings.maxCachedImages, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }

                        SettingsToggleRow(
                            title: "Preload next image",
                            description: "Load the next image in background for smoother transitions",
                            isOn: $viewModel.settings.advancedSettings.preloadNextImage
                        )
                    }
                }
            }

            // File Size Filters
            SettingsGroup(title: "File Size Limits", icon: "doc.text.magnifyingglass") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Minimum file size:")
                                    .font(.caption)
                                Text("(0 = no limit)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                TextField("Bytes", value: $viewModel.settings.fileFilters.minimumFileSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Text("bytes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Maximum file size:")
                                    .font(.caption)
                                Text("(0 = no limit)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                TextField("Bytes", value: $viewModel.settings.fileFilters.maximumFileSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Text("bytes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Debugging
            SettingsGroup(title: "Debugging", icon: "ant") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: "Enable detailed logging",
                        description: "Log detailed information for troubleshooting",
                        isOn: $viewModel.settings.advancedSettings.enableDetailedLogging
                    )

                    if viewModel.settings.advancedSettings.enableDetailedLogging {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                            Text("Detailed logging may impact performance")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }

            // System Recommendations
            if !viewModel.getSystemRecommendations().isEmpty {
                SettingsGroup(title: "Recommendations", icon: "lightbulb") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.getSystemRecommendations(), id: \.self) { recommendation in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 14))
                                Text(recommendation)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
            }

            // Reset Button
            VStack(spacing: 16) {
                Divider()

                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        viewModel.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Spacer(minLength: 20)
        }
    }
}

// MARK: - Helper Views

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16, weight: .medium))

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle())
        }
    }
}

struct SettingsPickerRow<SelectionValue: Hashable>: View {
    let title: String
    let description: String
    @Binding var selection: SelectionValue
    let options: [(value: SelectionValue, label: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300, alignment: .leading)
        }
    }
}

// MARK: - Toast Notification

struct ToastView: View {
    @Binding var isPresented: Bool
    let message: String

    var body: some View {
        VStack {
            Spacer()

            if isPresented {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))

                    Text(message)
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isPresented)
            }
        }
        .padding(.bottom, 20)
        .allowsHitTesting(false) // Allow clicks to pass through
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(settings: WallpaperSettings()))
}
