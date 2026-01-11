//
//  DisplaySettingsView.swift
//  wallpier
//
//  Display settings tab - Appearance, scaling, and multi-monitor configuration
//

import SwiftUI

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
                            .foregroundStyle(AppColors.primary)
                        Text("Using system accent color")
                            .captionStyle()
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
                    .captionStyle()
            }

            Section("Multi-Monitor Setup") {
                Toggle("Use same wallpaper on all monitors", isOn: $viewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors)

                HStack {
                    Image(systemName: "display")
                        .foregroundStyle(viewModel.settings.advancedSettings.accentColor)
                    Text("\(NSScreen.screens.count) monitor(s) detected")
                        .secondaryTextStyle()
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
                    .captionStyle()
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
