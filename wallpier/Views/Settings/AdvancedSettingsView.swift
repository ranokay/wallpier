//
//  AdvancedSettingsView.swift
//  wallpier
//
//  Advanced settings tab - Performance, cache, debugging
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Performance") {
                Text("Image Cache")
                    .headlineStyle()

                HStack {
                    Text("Maximum cache size:")
                    Spacer()
                    TextField("", value: $viewModel.settings.advancedSettings.maxCacheSizeMB, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    Text("MB")
                        .secondaryTextStyle()
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
                        .secondaryTextStyle()
                        .frame(width: 50, alignment: .leading)
                }

                Toggle("Preload next image", isOn: $viewModel.settings.advancedSettings.preloadNextImage)

                Divider()

                Text("Memory Usage")
                    .headlineStyle()

                HStack {
                    Text("Warning threshold:")
                    Spacer()
                    TextField("", value: $viewModel.settings.advancedSettings.memoryUsageLimitMB, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    Text("MB")
                        .secondaryTextStyle()
                        .frame(width: 50, alignment: .leading)
                }
                Text("Set to 0 to disable memory usage warnings. Higher values reduce log spam for large image collections.")
                    .captionStyle()
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
                        .secondaryTextStyle()
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
                        .secondaryTextStyle()
                        .frame(width: 50, alignment: .leading)
                }
                Text("Set to 0 for no limit.")
                    .captionStyle()
            }

            Section("Debugging") {
                Toggle("Enable detailed logging", isOn: $viewModel.settings.advancedSettings.enableDetailedLogging)
               if viewModel.settings.advancedSettings.enableDetailedLogging {
                    Label("Detailed logging may impact performance", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.warning)
                }
            }

            if !viewModel.getSystemRecommendations().isEmpty {
                Section("Recommendations") {
                    ForEach(viewModel.getSystemRecommendations(), id: \.self) { recommendation in
                        Label(recommendation, systemImage: "lightbulb.fill")
                            .foregroundColor(AppColors.warning)
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
