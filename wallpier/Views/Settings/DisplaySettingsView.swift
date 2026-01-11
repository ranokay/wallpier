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

}
