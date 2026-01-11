//
//  AdvancedSettingsView.swift
//  wallpier
//
//  Advanced settings tab - Performance, cache, debugging
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject var wallpaperViewModel: WallpaperViewModel

    private enum FieldWidth {
        static let input: CGFloat = 120
        static let unit: CGFloat = 44
    }

    private var cacheStats: ImageCacheService.CacheStatistics {
        wallpaperViewModel.cacheService.getCacheStatistics()
    }

    private var lastScanDescription: String {
        guard let last = wallpaperViewModel.lastScanCompletedAt else { return "No scans yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: last, relativeTo: Date())
    }

    private func formattedSeconds(_ value: TimeInterval) -> String {
        String(format: "%.3fs", value)
    }

    // MARK: - Unit Bindings (bytes ⇄ MB)

    private var minFileSizeMB: Binding<Double> {
        Binding {
            Double(viewModel.settings.fileFilters.minimumFileSize) / 1_000_000
        } set: { newValue in
            viewModel.settings.fileFilters.minimumFileSize = max(0, Int(newValue * 1_000_000))
        }
    }

    private var maxFileSizeMB: Binding<Double> {
        Binding {
            Double(viewModel.settings.fileFilters.maximumFileSize) / 1_000_000
        } set: { newValue in
            viewModel.settings.fileFilters.maximumFileSize = max(0, Int(newValue * 1_000_000))
        }
    }

    var body: some View {
        Form {
            Section("Performance") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Image Cache").headlineStyle()

                    metricRow(
                        title: "Maximum cache size",
                        unit: "MB",
                        field: { numberField($viewModel.settings.advancedSettings.maxCacheSizeMB) }
                    )

                    metricRow(
                        title: "Maximum cached images",
                        field: { numberField($viewModel.settings.advancedSettings.maxCachedImages) }
                    )

                    Toggle("Preload next image", isOn: $viewModel.settings.advancedSettings.preloadNextImage)

                    metricRow(
                        title: "Cache usage",
                        icon: "internaldrive",
                        value: "\(cacheStats.formattedSize) / \(viewModel.settings.advancedSettings.maxCacheSizeMB) MB"
                    )

                    metricRow(
                        title: "Max cached images",
                        icon: "number",
                        value: "\(viewModel.settings.advancedSettings.maxCachedImages)"
                    )

                    metricRow(
                        title: "Average change time",
                        icon: "timer",
                        value: formattedSeconds(wallpaperViewModel.averageChangeDuration)
                    )

                    metricRow(
                        title: "Last scan",
                        icon: "clock.arrow.circlepath",
                        value: lastScanDescription
                    )

                    Button {
                        wallpaperViewModel.cacheService.clearCache()
                        viewModel.showToast(message: "Cache cleared")
                    } label: {
                        Label("Clear cache", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, Spacing.sm)

                    Divider()

                    Text("Memory Usage").headlineStyle()

                    metricRow(
                        title: "Warning threshold",
                        unit: "MB",
                        field: { numberField($viewModel.settings.advancedSettings.memoryUsageLimitMB) }
                    )

                    Text("Set to 0 to disable memory usage warnings. Higher values reduce log spam for large image collections.")
                        .captionStyle()
                        .padding(.top, Spacing.xs)
                }
            }

            Section("File Size Limits") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    metricRow(
                        title: "Minimum file size",
                        unit: "MB",
                        field: { decimalField(minFileSizeMB) }
                    )

                    metricRow(
                        title: "Maximum file size",
                        unit: "MB",
                        field: { decimalField(maxFileSizeMB) }
                    )

                    Text("Set to 0 for no limit.")
                        .captionStyle()
                        .padding(.top, Spacing.xs)
                }
            }

            Section("Debugging") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toggle("Enable detailed logging", isOn: $viewModel.settings.advancedSettings.enableDetailedLogging)
                    Toggle("Disable App Intents metadata extraction", isOn: $viewModel.settings.advancedSettings.disableAppIntentsMetadataExtraction)

                    if viewModel.settings.advancedSettings.enableDetailedLogging {
                        Label("Detailed logging may impact performance", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                    }
                }
            }

            if !viewModel.getSystemRecommendations().isEmpty {
                Section("Recommendations") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(viewModel.getSystemRecommendations(), id: \.self) { recommendation in
                            Label(recommendation, systemImage: "lightbulb.fill")
                                .foregroundColor(AppColors.warning)
                        }
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

    // MARK: - Row Builders

    private func metricRow<Field: View>(title: String, icon: String? = nil, unit: String? = nil, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Label(titleWithUnit(title: title, unit: unit), systemImage: icon)
            } else {
                Text(titleWithUnit(title: title, unit: unit))
            }

            Spacer()

            field()
                .frame(width: FieldWidth.input, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }

    private func titleWithUnit(title: String, unit: String?) -> String {
        guard let unit else { return title }
        return "\(title) (\(unit))"
    }

    private func metricRow(title: String, icon: String? = nil, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
            Spacer()
            Text(value)
                .secondaryTextStyle()
        }
    }

    private func numberField<T: BinaryInteger>(_ binding: Binding<T>) -> some View {
        TextField("", value: binding, format: IntegerFormatStyle<T>())
            .textFieldStyle(.roundedBorder)
    }

    private func decimalField(_ binding: Binding<Double>) -> some View {
        TextField("", value: binding, format: .number.precision(.fractionLength(1)))
            .textFieldStyle(.roundedBorder)
    }
}
