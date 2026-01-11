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
        case display = "Display"
        case system = "System"
        case advanced = "Advanced"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .display: return "display"
            case .system: return "macwindow"
            case .advanced: return "cpu"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            DisplaySettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Display", systemImage: "display")
                }
                .tag(SettingsTab.display)

            SystemSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("System", systemImage: "macwindow")
                }
                .tag(SettingsTab.system)

            AdvancedSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Advanced", systemImage: "cpu")
                }
                .tag(SettingsTab.advanced)

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 550, height: 400)
        .padding()
        .overlay(
            // Toast notification overlay
            ToastView(
                isPresented: $viewModel.showToast,
                message: viewModel.toastMessage
            )
        )
        // Buttons removed as standard Settings windows auto-save or have simple close behavior
        // Wallpier's SettingsViewModel has explicit save/cancel, providing a "Close" button in toolbar is better
        // But for now, user wants UI style refactor.
        // We'll add a Toolbar for the Save/Close actions.
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    viewModel.cancelChanges()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.saveSettings()
                    // Optional: dismiss() on save? Usually yes for modal settings.
                     dismiss()
                }
                .disabled(viewModel.validationErrors.isEmpty == false)
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
        Form {
            Section("Application Behavior") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.systemIntegration?.launchAtStartup ?? false },
                    set: { enabled in
                        Task {
                            let _ = await SystemService().setLaunchAtStartup(enabled)
                            viewModel.settings.systemIntegration?.launchAtStartup = enabled
                        }
                    }
                )) {
                    Text("Launch at startup")
                    Text("Automatically start Wallpier when you log in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Launch at startup")
                .accessibilityHint("Automatically start Wallpier when you log in")

                Toggle(isOn: $viewModel.settings.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("Display a menu bar icon for quick access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Show menu bar icon")
                .accessibilityHint("Display a menu bar icon for quick access")

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.systemIntegration?.hideDockIcon ?? false },
                        set: { enabled in
                            SystemService().configureDockVisibility(!enabled)
                            viewModel.settings.systemIntegration?.hideDockIcon = enabled
                        }
                    )) {
                        Text("Hide dock icon")
                        Text("Remove app from dock (menu bar only mode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if viewModel.settings.systemIntegration?.hideDockIcon == true {
                        Text("Restart required for dock changes to take full effect")
                            .font(.caption)
                            .foregroundColor(.blue)
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
                            .foregroundColor(.blue)
                        Text(viewModel.statusMessage)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Display Settings


struct DisplaySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var useCustomAccentColor: Bool = false
    @State private var customAccentColor: Color = .blue

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Use custom accent color", isOn: $useCustomAccentColor)
                    .onChange(of: useCustomAccentColor) { _, newValue in
                        if !newValue {
                            viewModel.settings.advancedSettings.accentColorHex = nil
                        } else {
                            viewModel.settings.advancedSettings.setAccentColor(customAccentColor)
                        }
                    }
                    .accessibilityLabel("Use custom accent color")
                    .accessibilityHint("Enable to use a custom accent color instead of the system color")

                if useCustomAccentColor {
                    ColorPicker("Accent Color", selection: $customAccentColor, supportsOpacity: false)
                        .onChange(of: customAccentColor) { _, newColor in
                            viewModel.settings.advancedSettings.setAccentColor(newColor)
                        }
                        .accessibilityLabel("Accent color picker")
                        .accessibilityHint("Choose your custom accent color")
                }

                if !useCustomAccentColor {
                    HStack {
                        Image(systemName: "paintbrush")
                            .foregroundStyle(Color.accentColor)
                        Text("Using system accent color")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            Section("Wallpaper Display") {
                Picker("Scaling Mode", selection: $viewModel.settings.scalingMode) {
                    ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(scalingModeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Multi-Monitor Setup") {
                Toggle("Use same wallpaper on all monitors", isOn: $viewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors)

                HStack {
                    Image(systemName: "display")
                        .foregroundStyle(viewModel.settings.advancedSettings.accentColor)
                    Text("\(NSScreen.screens.count) monitor(s) detected")
                        .foregroundColor(.secondary)
                }

                if !viewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
                    ForEach(viewModel.availableDisplayNames, id: \.self) { displayName in
                        Picker(displayName, selection: Binding(
                            get: { viewModel.perMonitorScalingMode(for: displayName) },
                            set: { viewModel.setPerMonitorScalingMode($0, for: displayName) }
                        )) {
                             ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                                 Text(mode.displayName).tag(mode)
                             }
                        }
                    }
                }
            }

            Section("Supported File Types") {
                Toggle("HEIC files", isOn: $viewModel.settings.fileFilters.includeHEICFiles)
                    .accessibilityLabel("Include HEIC files")
                    .accessibilityHint("Include HEIC format images in wallpaper scanning")
                Toggle("GIF files", isOn: $viewModel.settings.fileFilters.includeGIFFiles)
                    .accessibilityLabel("Include GIF files")
                    .accessibilityHint("Include GIF format images in wallpaper scanning")
                Toggle("WebP files", isOn: $viewModel.settings.fileFilters.includeWebPFiles)
                    .accessibilityLabel("Include WebP files")
                    .accessibilityHint("Include WebP format images in wallpaper scanning")

                Label("Always included: JPEG, PNG, BMP, TIFF", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Initialize state from settings
            useCustomAccentColor = viewModel.settings.advancedSettings.accentColorHex != nil
            if let hex = viewModel.settings.advancedSettings.accentColorHex,
               let color = Color(hex: hex) {
                customAccentColor = color
            }
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
        Form {
            Section("System Behavior") {
                Toggle("Pause when screen is locked", isOn: Binding(
                    get: { viewModel.settings.systemIntegration?.pauseWhenScreenLocked ?? false },
                    set: { viewModel.settings.systemIntegration?.pauseWhenScreenLocked = $0 }
                ))
                Toggle("Pause during presentations", isOn: Binding(
                    get: { viewModel.settings.systemIntegration?.pauseDuringPresentations ?? true },
                    set: { viewModel.settings.systemIntegration?.pauseDuringPresentations = $0 }
                ))
            }

            Section("Permissions & Status") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("File System Access")
                        Spacer()
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundColor(systemService.permissionStatus.isFullyGranted ? .green : .orange)
                        Text(permissionStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Wallpier only accesses folders you explicitly select")
                        .font(.caption2)
                        .foregroundColor(.secondary)

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

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Performance") {
                Text("Image Cache").font(.headline)

                HStack {
                    Text("Maximum cache size:")
                    Spacer()
                    TextField("", value: $viewModel.settings.advancedSettings.maxCacheSizeMB, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    Text("MB")
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }

                HStack {
                    Text("Maximum cached images:")
                    Spacer()
                    TextField("", value: $viewModel.settings.advancedSettings.maxCachedImages, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    Text("")
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }

                Toggle("Preload next image", isOn: $viewModel.settings.advancedSettings.preloadNextImage)

                Divider()

                Text("Memory Usage").font(.headline)

                HStack {
                    Text("Warning threshold:")
                    Spacer()
                    TextField("", value: $viewModel.settings.advancedSettings.memoryUsageLimitMB, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    Text("MB")
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }
                Text("Set to 0 to disable memory usage warnings. Higher values reduce log spam for large image collections.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("File Size Limits") {
                HStack {
                    Text("Minimum file size:")
                    Spacer()
                    TextField("", value: $viewModel.settings.fileFilters.minimumFileSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    Text("bytes")
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }
                HStack {
                    Text("Maximum file size:")
                    Spacer()
                    TextField("", value: $viewModel.settings.fileFilters.maximumFileSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    Text("bytes")
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }
                Text("Set to 0 for no limit.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Debugging") {
                Toggle("Enable detailed logging", isOn: $viewModel.settings.advancedSettings.enableDetailedLogging)
                if viewModel.settings.advancedSettings.enableDetailedLogging {
                    Label("Detailed logging may impact performance", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            if !viewModel.getSystemRecommendations().isEmpty {
                Section("Recommendations") {
                    ForEach(viewModel.getSystemRecommendations(), id: \.self) { recommendation in
                        Label(recommendation, systemImage: "lightbulb.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }

            Section {
                Button("Reset to Defaults") {
                    viewModel.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }
}
// Helper views (SettingsGroup, SettingsToggleRow, etc.) removed as they are no longer used.


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

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                // App Icon and Title
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundStyle(.linearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    Text("Wallpier")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Dynamic Wallpaper Cycling for macOS")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // App Info
                VStack(spacing: 8) {
                    HStack {
                        Text("Version")
                            .fontWeight(.medium)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                            .fontWeight(.medium)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Bundle ID")
                            .fontWeight(.medium)
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "com.oxystack.wallpier")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 300)

                Spacer(minLength: 20)

                // Copyright
                Text("© 2025 Oxystack. All rights reserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(settings: WallpaperSettings()))
}
