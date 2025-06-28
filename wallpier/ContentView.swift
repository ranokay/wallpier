//
//  ContentView.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var wallpaperViewModel = WallpaperViewModel()
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var showingSettings = false
    @State private var showingAbout = false

    init() {
        let settings = WallpaperSettings.load()
        self._settingsViewModel = StateObject(wrappedValue: SettingsViewModel(settings: settings))
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 20) {
                // App Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Wallpier")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    Text("Dynamic Wallpaper Cycling")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Divider()

                // Control Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Control", systemImage: "gearshape.fill")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(spacing: 8) {
                        // Start/Stop Button
                        Button(action: toggleCycling) {
                            HStack {
                                Image(systemName: wallpaperViewModel.isRunning ? "stop.circle.fill" : "play.circle.fill")
                                Text(wallpaperViewModel.isRunning ? "Stop Cycling" : "Start Cycling")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!wallpaperViewModel.canStartCycling)

                        // Manual Navigation
                        HStack {
                            Button(action: { wallpaperViewModel.goToPreviousImage() }) {
                                Image(systemName: "backward.fill")
                            }
                            .disabled(!wallpaperViewModel.canGoBack)

                            Spacer()

                            Button(action: { wallpaperViewModel.goToNextImage() }) {
                                Image(systemName: "forward.fill")
                            }
                            .disabled(!wallpaperViewModel.canAdvance)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)

                Divider()

                // Quick Settings
                VStack(alignment: .leading, spacing: 12) {
                    Label("Quick Settings", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(spacing: 8) {
                        // Folder Selection
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Folder")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: selectFolder) {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(folderDisplayName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        // Interval Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Interval")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Interval", selection: $wallpaperViewModel.cyclingInterval) {
                                ForEach(WallpaperSettings.commonIntervals, id: \.seconds) { interval in
                                    Text(interval.name).tag(interval.seconds)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        // Shuffle Toggle
                        Toggle("Shuffle Images", isOn: $wallpaperViewModel.isShuffleEnabled)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Settings Button
                VStack(spacing: 8) {
                    Button("Settings", action: { showingSettings = true })
                        .buttonStyle(.bordered)

                    Button("About", action: { showingAbout = true })
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.horizontal)
            }
            .frame(minWidth: 250, maxWidth: 300)
            .padding(.vertical)

        } detail: {
            // Main Content Area
            VStack(spacing: 20) {
                // Status Header
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Current Status")
                                .font(.headline)
                            Text(wallpaperViewModel.statusMessage.isEmpty ? "Ready" : wallpaperViewModel.statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Status Indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if wallpaperViewModel.isScanning {
                        ProgressView("Scanning images...")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Current Image Preview
                if let currentImage = wallpaperViewModel.currentImage {
                    CurrentImageView(imageFile: currentImage)
                } else {
                    // Placeholder
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

                // Image Queue Info
                if !wallpaperViewModel.foundImages.isEmpty {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(wallpaperViewModel.foundImages.count) Images Found")
                                .font(.headline)
                            Text("Progress: \(Int(wallpaperViewModel.cycleProgress * 100))%")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Rescan", action: { wallpaperViewModel.rescanCurrentFolder() })
                            .buttonStyle(.bordered)
                            .disabled(wallpaperViewModel.isScanning)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
            .frame(minWidth: 400, minHeight: 300)
        }
        .navigationTitle("Wallpier")
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: settingsViewModel)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .onReceive(settingsViewModel.$settings) { newSettings in
            wallpaperViewModel.updateSettings(newSettings)
        }
        .task {
            await wallpaperViewModel.loadInitialData()
        }
    }

    // MARK: - Computed Properties

    private var folderDisplayName: String {
        wallpaperViewModel.selectedFolderPath?.lastPathComponent ?? "None Selected"
    }

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

    // MARK: - Actions

    private func toggleCycling() {
        if wallpaperViewModel.isRunning {
            wallpaperViewModel.stopCycling()
        } else {
            Task { await wallpaperViewModel.startCycling() }
        }
    }

    private func selectFolder() {
        settingsViewModel.selectFolder()
    }
}

// MARK: - Supporting Views

struct CurrentImageView: View {
    let imageFile: ImageFile
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 12) {
            // Image Preview
            Group {
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay {
                            ProgressView()
                        }
                }
            }
            .frame(maxHeight: 300)

            // Image Info
            VStack(alignment: .leading, spacing: 4) {
                Text(imageFile.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack {
                    Text(imageFile.formattedSize)
                    Spacer()
                    Text(imageFile.modificationDate, style: .date)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let loadedImage = NSImage(contentsOf: imageFile.url)
                DispatchQueue.main.async {
                    continuation.resume(returning: loadedImage)
                }
            }
        }
    }
}

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
}
