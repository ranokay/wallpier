//
//  SidebarView.swift
//  wallpier
//
//  Sidebar component with quick settings and controls
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Control Section
            VStack(alignment: .leading, spacing: Spacing.listItemSpacing) {
                Label("Control", systemImage: "gearshape.fill")
                    .headlineStyle()

                // Manual Navigation Controls
                HStack(spacing: Spacing.buttonSpacing) {
                    Button(action: { wallpaperViewModel.goToPreviousImage() }) {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!wallpaperViewModel.canGoBack)
                    .accessibilityLabel("Previous image")
                    .accessibilityHint("Go to the previous wallpaper image")

                    Spacer()

                    // Start/Stop Button
                    Group {
                        if wallpaperViewModel.isRunning {
                            Button(action: toggleCycling) {
                                HStack {
                                    Image(systemName: "stop.circle.fill")
                                    Text("Stop")
                                }
                                .frame(minWidth: 80)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Stop cycling")
                            .accessibilityHint("Stop automatic wallpaper cycling")
                        } else {
                            Button(action: toggleCycling) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                    Text("Start")
                                }
                                .frame(minWidth: 80)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!wallpaperViewModel.canStartCycling)
                            .accessibilityLabel("Start cycling")
                            .accessibilityHint("Start automatic wallpaper cycling")
                        }
                    }

                    Spacer()

                    Button(action: { wallpaperViewModel.goToNextImage() }) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!wallpaperViewModel.canAdvance)
                    .accessibilityLabel("Next image")
                    .accessibilityHint("Go to the next wallpaper image")
                }
            }
            .padding(.horizontal, Spacing.lg)

            Divider()

            // Quick Settings Section
            VStack(alignment: .leading, spacing: Spacing.listItemSpacing) {
                Label("Quick Settings", systemImage: "slider.horizontal.3")
                    .headlineStyle()

                VStack(alignment: .leading, spacing: Spacing.listItemSpacing) {
                    // Folder Selection
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Folder")
                            .captionStyle()

                        Button(action: selectFolder) {
                            HStack {
                                Image(systemName: "folder")
                                Text(folderDisplayName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(AppColors.contentSecondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Select wallpaper folder")
                        .accessibilityValue(folderDisplayName)
                        .accessibilityHint("Choose a folder containing wallpaper images")
                    }

                    // Interval Picker
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Interval")
                            .captionStyle()

                        HStack {
                            Picker("Interval", selection: $wallpaperViewModel.cyclingInterval) {
                                ForEach(WallpaperSettings.commonIntervals, id: \.seconds) { interval in
                                    Text(interval.name).tag(interval.seconds)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityLabel("Cycling interval")
                            .accessibilityHint("Choose how often the wallpaper changes")

                            Spacer()
                        }
                    }

                    // Scaling Mode Picker (NEW - moved from Settings)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Scaling")
                            .captionStyle()

                        HStack {
                            Picker("Scaling", selection: $settingsViewModel.settings.scalingMode) {
                                ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .onChange(of: settingsViewModel.settings.scalingMode) { _, _ in
                                settingsViewModel.saveSettings()
                            }
                            .accessibilityLabel("Image scaling mode")
                            .accessibilityHint("Choose how images are scaled to fit the screen")

                            Spacer()
                        }
                    }

                    // Sort Order Picker (NEW - now prominently accessible)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Sort Order")
                            .captionStyle()

                        HStack {
                            Picker("Sort Order", selection: $settingsViewModel.settings.sortOrder) {
                                ForEach(ImageSortOrder.allCases, id: \.self) { order in
                                    Text(order.displayName).tag(order)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .onChange(of: settingsViewModel.settings.sortOrder) { _, _ in
                                settingsViewModel.saveSettings()
                            }
                            .accessibilityLabel("Image sort order")
                            .accessibilityHint("Choose how images are ordered in the queue")

                            Spacer()
                        }
                    }

                    // Multi-Monitor Toggle (NEW - moved from Settings)
                    Toggle("Same on all monitors", isOn: $settingsViewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors)
                        .onChange(of: settingsViewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors) { _, _ in
                            settingsViewModel.saveSettings()
                        }
                        .accessibilityLabel("Use same wallpaper on all monitors")
                        .accessibilityHint("When enabled, the same wallpaper is shown on all displays")

                    if !settingsViewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Per-Monitor Scaling")
                                .captionStyle()

                            ForEach(settingsViewModel.availableDisplayNames, id: \.self) { displayName in
                                HStack {
                                    Text(displayName)
                                        .secondaryTextStyle()
                                    Spacer()
                                    Picker(displayName, selection: Binding(
                                        get: { settingsViewModel.perMonitorScalingMode(for: displayName) },
                                        set: { newValue in
                                            settingsViewModel.setPerMonitorScalingMode(newValue, for: displayName)
                                            settingsViewModel.saveSettings()
                                        }
                                    )) {
                                        ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                                            Text(mode.displayName).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }
                            }
                        }
                    }

                    // Shuffle Toggle
                    Toggle("Shuffle Images", isOn: $wallpaperViewModel.isShuffleEnabled)
                        .accessibilityLabel("Shuffle images")
                        .accessibilityHint("When enabled, images are shown in random order")

                    // Scan Subfolders Toggle
                    Toggle("Scan Subfolders", isOn: $settingsViewModel.settings.isRecursiveScanEnabled)
                        .onChange(of: settingsViewModel.settings.isRecursiveScanEnabled) { _, _ in
                            settingsViewModel.saveSettings()
                        }
                        .accessibilityLabel("Scan subfolders")
                        .accessibilityHint("When enabled, images from subfolders are also included")
                }
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            // Settings Button
            Button("More Settings...", action: { showingSettings = true })
                .buttonStyle(.bordered)
                .padding(.horizontal, Spacing.lg)
                .accessibilityLabel("Open settings")
                .accessibilityHint("Open the full application settings window")
        }
        .padding(.vertical, Spacing.lg)
        .frame(width: Spacing.sidebarWidth)
        .background(AppColors.backgroundTertiary)
    }

    // MARK: - Computed Properties

    private var folderDisplayName: String {
        wallpaperViewModel.selectedFolderPath?.lastPathComponent ?? "None Selected"
    }

    // MARK: - Actions

    private func toggleCycling() {
        if wallpaperViewModel.isRunning {
            wallpaperViewModel.stopCycling()
        } else {
            Task { await wallpaperViewModel.startCycling() }
        }
    }

    private func selectFolder() {
        settingsViewModel.selectFolderAndSaveImmediately()
    }
}
