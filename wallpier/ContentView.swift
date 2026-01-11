//
//  ContentView.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI

// MARK: - Native Progress Indicator (avoids SwiftUI ProgressView Auto Layout warnings)

struct NativeProgressIndicator: NSViewRepresentable {
    var size: NSControl.ControlSize = .small

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = size
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        nsView.controlSize = size
    }
}

struct ContentView: View {
    @EnvironmentObject var wallpaperViewModel: WallpaperViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var showingSettings = false
    @State private var showingWallpaperGallery = false
    @State private var selectedScreenForGallery: NSScreen?

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(
                wallpaperViewModel: wallpaperViewModel,
                settingsViewModel: settingsViewModel,
                showingSettings: $showingSettings
            )

            Divider()

            // Main Content Area
            ScrollView {
                VStack(spacing: 20) {
                    // Status Header
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Status")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text(wallpaperViewModel.statusMessage.isEmpty ? "Ready" : wallpaperViewModel.statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Status Indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: statusColor.opacity(0.5), radius: 4, x: 0, y: 0)
                            Text(statusText)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(statusColor == .green ? .primary : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )

                    // Scanning indicator (separate for cleaner animations)
                    if wallpaperViewModel.isScanning {
                        HStack(spacing: 10) {
                            NativeProgressIndicator(size: .small)
                                .frame(width: 16, height: 16)
                            Text("Scanning images...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Current Image Preview(s)
                    Group {
                        if wallpaperViewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
                            // Single image preview
                            if let currentImage = wallpaperViewModel.currentImage {
                                ImagePreviewView(imageFile: currentImage)
                                    .id(currentImage.url)
                                    .transition(.opacity)
                            } else {
                                placeholderView
                                    .transition(.opacity)
                            }
                        } else if !wallpaperViewModel.currentImages.isEmpty {
                            // Multi-monitor preview
                            MultiMonitorPreviewView(
                                currentImages: wallpaperViewModel.currentImages,
                                availableScreens: wallpaperViewModel.availableScreens,
                                isInteractive: !wallpaperViewModel.isRunning,
                                onScreenTapped: { screen in
                                    selectedScreenForGallery = screen
                                    showingWallpaperGallery = true
                                }
                            )
                        } else {
                            placeholderView
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: wallpaperViewModel.currentImage?.url)

                    // Image Queue Info
                    if !wallpaperViewModel.foundImages.isEmpty {
                        HStack(spacing: 16) {
                            Text("\(wallpaperViewModel.foundImages.count) Images Found")
                                .font(.headline)

                            Spacer()

                            HStack(spacing: 10) {
                                Button {
                                    wallpaperViewModel.rescanCurrentFolder()
                                } label: {
                                    Label("Rescan", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .disabled(wallpaperViewModel.isScanning)

                                Button {
                                    selectedScreenForGallery = nil
                                    showingWallpaperGallery = true
                                } label: {
                                    Label("Browse Wallpapers", systemImage: "square.grid.2x2")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(wallpaperViewModel.foundImages.isEmpty)
                            }
                        }
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: wallpaperViewModel.isScanning)
            }
            .frame(minWidth: 500)
        }
        .navigationTitle("Wallpier")
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: settingsViewModel)
        }
        .sheet(isPresented: $showingWallpaperGallery) {
            WallpaperGalleryView(
                images: wallpaperViewModel.foundImages,
                targetScreen: selectedScreenForGallery,
                availableScreens: wallpaperViewModel.availableScreens,
                useSameWallpaperOnAllMonitors: wallpaperViewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors,
                cacheService: wallpaperViewModel.cacheService,
                onWallpaperSelected: { imageFile, screen in
                    Task {
                        if let screen = screen {
                            await wallpaperViewModel.setWallpaperForScreen(imageFile, screen: screen)
                        } else {
                            await wallpaperViewModel.setWallpaperOnAllScreens(imageFile)
                        }
                    }
                    showingWallpaperGallery = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerWallpaperGallery"))) { _ in
            // Open wallpaper gallery from menu bar
            selectedScreenForGallery = nil
            showingWallpaperGallery = true
        }
        .onAppear {
            // Set up the settings callback to ensure proper updates
            settingsViewModel.onSettingsSaved = { newSettings in
                wallpaperViewModel.updateSettings(newSettings)
            }
            // Note: Initial settings sync is done in wallpierApp.onAppear
        }
        .task {
            await wallpaperViewModel.loadInitialData()
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if wallpaperViewModel.isRunning {
            return .green
        } else if wallpaperViewModel.hasError {
            return .red
        } else {
            return .secondary
        }
    }

    private var statusText: String {
        if wallpaperViewModel.isRunning {
            return "Running"
        } else if wallpaperViewModel.hasError {
            return "Error"
        } else {
            return "Stopped"
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Images Selected")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("Choose a folder with images to start cycling wallpapers")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Select Folder", action: selectFolder)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Supporting Views

// Note: Extracted components moved to separate files:
// - ImagePreviewView (formerly OptimizedImageView) -> Views/Components/ImagePreviewView.swift
// - MultiMonitorPreviewView -> Views/Components/MultiMonitorPreviewView.swift
// - ScreenPreviewCard -> Views/Components/ScreenPreviewCard.swift
// - SidebarView -> Views/Components/SidebarView.swift
// - WallpaperGalleryView -> Views/Gallery/WallpaperGalleryView.swift
// - WallpaperThumbnail -> Views/Gallery/WallpaperThumbnail.swift

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // App Icon and Title
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("Wallpier")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Dynamic Wallpaper Cycling for macOS")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // App Info
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Version", value: "1.0.0")
                InfoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                InfoRow(label: "Bundle ID", value: "com.oxystack.wallpier")
            }

            Spacer()

            // Close Button
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperViewModel())
        .environmentObject(SettingsViewModel(settings: WallpaperSettings()))
}
