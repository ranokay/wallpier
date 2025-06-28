//
//  ContentView.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var wallpaperViewModel: WallpaperViewModel
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingWallpaperGallery = false
    @State private var selectedScreenForGallery: NSScreen?

    init() {
        let settings = WallpaperSettings.load()
        self._settingsViewModel = StateObject(wrappedValue: SettingsViewModel(settings: settings))

        // Setup the callback after the StateObject is created
        // We'll do this in onAppear since we can't access StateObject's wrappedValue in init
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

                    // Manual Navigation
                    HStack(spacing: 5) {
                        Button(action: { wallpaperViewModel.goToPreviousImage() }) {
                            Image(systemName: "backward.fill")
                        }
                        .disabled(!wallpaperViewModel.canGoBack)

                        Spacer()

                        // Start/Stop Button
                        Button(action: toggleCycling) {
                            HStack {
                                Image(systemName: wallpaperViewModel.isRunning ? "stop.circle.fill" : "play.circle.fill")
                                Text(wallpaperViewModel.isRunning ? "Stop" : "Start")
                            }
                            .frame(minWidth: 80)
                        }
                        .buttonStyle(ControlButton(isProminent: !wallpaperViewModel.isRunning))
                        .disabled(wallpaperViewModel.isRunning ? false : !wallpaperViewModel.canStartCycling)

                        Spacer()

                        Button(action: { wallpaperViewModel.goToNextImage() }) {
                            Image(systemName: "forward.fill")
                        }
                        .disabled(!wallpaperViewModel.canAdvance)
                    }
                    .buttonStyle(ControlButton(isProminent: false))
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
                            .buttonStyle(ControlButton(isProminent: false))
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
                        .buttonStyle(ControlButton(isProminent: false))

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

                // Current Image Preview(s)
                if wallpaperViewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
                    // Single image preview
                    if let currentImage = wallpaperViewModel.currentImage {
                        OptimizedImageView(imageFile: currentImage)
                            .id(currentImage.url)
                    } else {
                        placeholderView
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

                        HStack(spacing: 8) {
                            Button("Rescan", action: { wallpaperViewModel.rescanCurrentFolder() })
                                .buttonStyle(ControlButton(isProminent: false))
                                .disabled(wallpaperViewModel.isScanning)

                            Button("Browse Wallpapers") {
                                selectedScreenForGallery = nil
                                showingWallpaperGallery = true
                            }
                            .buttonStyle(ControlButton(isProminent: false))
                            .disabled(wallpaperViewModel.foundImages.isEmpty)
                        }
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
        .sheet(isPresented: $showingWallpaperGallery) {
            WallpaperGalleryView(
                images: wallpaperViewModel.foundImages,
                targetScreen: selectedScreenForGallery,
                availableScreens: wallpaperViewModel.availableScreens,
                useSameWallpaperOnAllMonitors: wallpaperViewModel.settings.multiMonitorSettings.useSameWallpaperOnAllMonitors,
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
        .onReceive(settingsViewModel.$settings) { newSettings in
            wallpaperViewModel.updateSettings(newSettings)
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

            // Sync initial settings immediately to ensure WallpaperViewModel has the correct state
            wallpaperViewModel.updateSettings(settingsViewModel.settings)
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
                    .buttonStyle(ControlButton(isProminent: true))
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
        settingsViewModel.selectFolder()
    }
}

// MARK: - Custom Styles

struct ControlButton: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isProminent ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundColor(isProminent ? .white : .primary)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Supporting Views

/// Optimized image view with downscaled previews for better performance
struct OptimizedImageView: View {
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
                                .controlSize(.small)
                                .frame(width: 20, height: 20)
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
            await loadOptimizedImage()
        }
    }

    private func loadOptimizedImage() async {
        // Use optimized loading from PerformanceMonitor
        image = await PerformanceMonitor.loadOptimizedPreview(from: imageFile.url, maxSize: 400)
    }
}

/// Multi-monitor preview showing current wallpapers for each screen
struct MultiMonitorPreviewView: View {
    let currentImages: [NSScreen: ImageFile]
    let availableScreens: [(screen: NSScreen, displayName: String)]
    let isInteractive: Bool
    let onScreenTapped: ((NSScreen) -> Void)?
    @State private var previewImages: [NSScreen: NSImage?] = [:]

    var body: some View {
        VStack(spacing: 16) {
            Text("Multi-Monitor Wallpapers")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if availableScreens.count <= 2 {
                // Horizontal layout for 1-2 screens
                HStack(spacing: 12) {
                    ForEach(availableScreens, id: \.screen) { screenInfo in
                        ScreenPreviewCard(
                            screenInfo: screenInfo,
                            currentImage: currentImages[screenInfo.screen],
                            previewImage: previewImages[screenInfo.screen] ?? nil,
                            isInteractive: isInteractive,
                            onTapped: {
                                onScreenTapped?(screenInfo.screen)
                            }
                        )
                    }
                }
            } else {
                // Grid layout for 3+ screens
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach(availableScreens, id: \.screen) { screenInfo in
                        ScreenPreviewCard(
                            screenInfo: screenInfo,
                            currentImage: currentImages[screenInfo.screen],
                            previewImage: previewImages[screenInfo.screen] ?? nil,
                            isInteractive: isInteractive,
                            onTapped: {
                                onScreenTapped?(screenInfo.screen)
                            }
                        )
                    }
                }
            }
        }
        .task {
            await loadPreviewImages()
        }
        .onChange(of: currentImages) {
            Task {
                await loadPreviewImages()
            }
        }
    }

    private func loadPreviewImages() async {
        let imageURLs = currentImages.compactMap { $0.value.url }
        let loadedImages = await PerformanceMonitor.loadMultipleOptimizedPreviews(from: imageURLs, maxSize: 200)

        await MainActor.run {
            var newPreviewImages: [NSScreen: NSImage?] = [:]
            for (screen, imageFile) in currentImages {
                if let index = imageURLs.firstIndex(of: imageFile.url),
                   index < loadedImages.count {
                    newPreviewImages[screen] = loadedImages[index]
                }
            }
            self.previewImages = newPreviewImages
        }
    }
}

/// Individual screen preview card
struct ScreenPreviewCard: View {
    let screenInfo: (screen: NSScreen, displayName: String)
    let currentImage: ImageFile?
    let previewImage: NSImage?
    let isInteractive: Bool
    let onTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            // Screen preview
            Group {
                if let nsImage = previewImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(6)
                } else if currentImage != nil {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 120)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.tertiarySystemFill))
                        .frame(height: 120)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "display")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("No Image")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            }

            // Screen info
            VStack(spacing: 2) {
                Text(screenInfo.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let imageName = currentImage?.name {
                    Text(imageName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No wallpaper")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isInteractive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isInteractive ? 1.0 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isInteractive)
        .onTapGesture {
            if isInteractive {
                onTapped?()
            }
        }
        .help(isInteractive ? "Click to change wallpaper for \(screenInfo.displayName)" : "")
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

/// Wallpaper gallery for manual selection
struct WallpaperGalleryView: View {
    let images: [ImageFile]
    let targetScreen: NSScreen?
    let availableScreens: [(screen: NSScreen, displayName: String)]
    let useSameWallpaperOnAllMonitors: Bool
    let onWallpaperSelected: (ImageFile, NSScreen?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreen: NSScreen?
    @State private var searchText = ""
    @State private var previewImages: [URL: NSImage] = [:]
    private let imageLoader = ImageLoader()

    private var filteredImages: [ImageFile] {
        if searchText.isEmpty {
            return images
        } else {
            return images.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 12) {
                    if useSameWallpaperOnAllMonitors {
                        Text("Choose wallpaper for all screens")
                            .font(.headline)
                    } else {
                        VStack(spacing: 8) {
                            Text("Choose wallpaper for:")
                                .font(.headline)

                            Picker("Target Screen", selection: $selectedScreen) {
                                Text("All Screens").tag(nil as NSScreen?)
                                ForEach(availableScreens, id: \.screen) { screenInfo in
                                    Text(screenInfo.displayName).tag(screenInfo.screen as NSScreen?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search wallpapers...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()

                // Gallery Grid
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(filteredImages, id: \.url) { imageFile in
                            WallpaperThumbnail(
                                imageFile: imageFile,
                                previewImage: previewImages[imageFile.url],
                                onTapped: {
                                    let targetScreen = useSameWallpaperOnAllMonitors ? nil : (selectedScreen ?? targetScreen)
                                    onWallpaperSelected(imageFile, targetScreen)
                                }
                            )
                            .task {
                                await loadThumbnail(for: imageFile)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Wallpaper Gallery")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            selectedScreen = targetScreen
            Task {
                let imageURLs = images.map { $0.url }
                let loadedImages = await imageLoader.loadMultiple(from: imageURLs, maxSize: 200)
                var newPreviewImages: [URL: NSImage] = [:]
                for (index, image) in loadedImages.enumerated() {
                    if let image = image {
                        newPreviewImages[imageURLs[index]] = image
                    }
                }
                self.previewImages = newPreviewImages
            }
        }
    }

    private func loadThumbnail(for imageFile: ImageFile) async {
        if previewImages[imageFile.url] == nil {
            let thumbnail = await PerformanceMonitor.loadOptimizedPreview(from: imageFile.url, maxSize: 150)
            await MainActor.run {
                previewImages[imageFile.url] = thumbnail
            }
        }
    }
}

/// Individual wallpaper thumbnail in the gallery
struct WallpaperThumbnail: View {
    let imageFile: ImageFile
    let previewImage: NSImage?
    let onTapped: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            Group {
                if let nsImage = previewImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 80)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 120, height: 80)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: isHovered ? 2 : 0)
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            // Name
            Text(imageFile.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 120)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTapped()
        }
    }
}

// MARK: - Image Loading Actor

actor ImageLoader {
    func load(from url: URL, maxSize: CGFloat) async -> NSImage? {
        return await PerformanceMonitor.loadOptimizedPreview(from: url, maxSize: maxSize)
    }

    func loadMultiple(from urls: [URL], maxSize: CGFloat) async -> [NSImage?] {
        return await PerformanceMonitor.loadMultipleOptimizedPreviews(from: urls, maxSize: maxSize)
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperViewModel())
        .environmentObject(SettingsViewModel(settings: WallpaperSettings()))
}
