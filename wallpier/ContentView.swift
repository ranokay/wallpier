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
            VStack(alignment: .leading, spacing: 20) {
                // Control Section
                VStack(alignment: .leading, spacing: 14) {
                    Label("Control", systemImage: "gearshape.fill")
                        .font(.headline)
                        .foregroundColor(.primary)

                    // Manual Navigation
                    HStack(spacing: 8) {
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
                .padding(.horizontal)

                Divider()

                // Quick Settings
                VStack(alignment: .leading, spacing: 12) {
                    Label("Quick Settings", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 12) {
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
                            .accessibilityLabel("Select wallpaper folder")
                            .accessibilityValue(folderDisplayName)
                            .accessibilityHint("Choose a folder containing wallpaper images")
                        }

                        // Interval Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Interval")
                                .font(.caption)
                                .foregroundColor(.secondary)

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

                        // Shuffle Toggle
                        Toggle("Shuffle Images", isOn: $wallpaperViewModel.isShuffleEnabled)
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Shuffle images")
                            .accessibilityHint("When enabled, images are shown in random order")

                        // Scan Subfolders Toggle
                        Toggle("Scan Subfolders", isOn: $settingsViewModel.settings.isRecursiveScanEnabled)
                            .toggleStyle(.checkbox)
                            .onChange(of: settingsViewModel.settings.isRecursiveScanEnabled) { _, _ in
                                settingsViewModel.saveSettings()
                            }
                            .accessibilityLabel("Scan subfolders")
                            .accessibilityHint("When enabled, images from subfolders are also included")
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Settings Button
                Button("Settings", action: { showingSettings = true })
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .accessibilityLabel("Open settings")
                    .accessibilityHint("Open the application settings window")
            }
            .padding(.vertical)
            .frame(width: 260)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

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
                                OptimizedImageView(imageFile: currentImage)
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

/// Optimized image view with downscaled previews for better performance
struct OptimizedImageView: View {
    let imageFile: ImageFile
    @State private var image: NSImage?
    @State private var isLoaded = false

    var body: some View {
        VStack(spacing: 12) {
            // Image Preview
            Group {
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(isLoaded ? 1 : 0)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .overlay {
                            NativeProgressIndicator(size: .small)
                                .frame(width: 20, height: 20)
                        }
                }
            }
            .frame(maxHeight: 300)
            .animation(.easeOut(duration: 0.15), value: isLoaded)

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
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .task {
            await loadOptimizedImage()
        }
    }

    private func loadOptimizedImage() async {
        // Use optimized loading from PerformanceMonitor
        image = await PerformanceMonitor.loadOptimizedPreview(from: imageFile.url, maxSize: 400)
        isLoaded = true
    }
}

/// Multi-monitor preview showing current wallpapers for each screen
struct MultiMonitorPreviewView: View {
    let currentImages: [ScreenID: ImageFile]
    let availableScreens: [(id: ScreenID, screen: NSScreen, displayName: String)]
    let isInteractive: Bool
    let onScreenTapped: ((NSScreen) -> Void)?
    @State private var previewImages: [ScreenID: NSImage?] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Multi-Monitor Wallpapers")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isInteractive {
                    Text("Click to change")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Center the preview cards horizontally
            HStack {
                Spacer()
                if availableScreens.count <= 2 {
                    // Horizontal layout for 1-2 screens
                    HStack(spacing: 20) {
                        ForEach(availableScreens, id: \.id) { screenInfo in
                            ScreenPreviewCard(
                                screenInfo: (screen: screenInfo.screen, displayName: screenInfo.displayName),
                                currentImage: currentImages[screenInfo.id],
                                previewImage: previewImages[screenInfo.id] ?? nil,
                                isInteractive: isInteractive,
                                onTapped: {
                                    onScreenTapped?(screenInfo.screen)
                                }
                            )
                        }
                    }
                } else {
                    // Grid layout for 3+ screens
                    LazyVGrid(columns: [GridItem(.fixed(286)), GridItem(.fixed(286))], spacing: 20) {
                        ForEach(availableScreens, id: \.id) { screenInfo in
                            ScreenPreviewCard(
                                screenInfo: (screen: screenInfo.screen, displayName: screenInfo.displayName),
                                currentImage: currentImages[screenInfo.id],
                                previewImage: previewImages[screenInfo.id] ?? nil,
                                isInteractive: isInteractive,
                                onTapped: {
                                    onScreenTapped?(screenInfo.screen)
                                }
                            )
                        }
                    }
                }
                Spacer()
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
            var newPreviewImages: [ScreenID: NSImage?] = [:]
            for (screenID, imageFile) in currentImages {
                if let index = imageURLs.firstIndex(of: imageFile.url),
                   index < loadedImages.count {
                    newPreviewImages[screenID] = loadedImages[index]
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
    @State private var isHovered = false

    // Fixed dimensions for 16:10 aspect ratio preview
    private let previewWidth: CGFloat = 256
    private let previewHeight: CGFloat = 160 // 256 * 10/16 = 160

    var body: some View {
        VStack(spacing: 10) {
            // Screen preview with fixed 16:10 aspect ratio
            Group {
                if let nsImage = previewImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: previewWidth, height: previewHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if currentImage != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .frame(width: previewWidth, height: previewHeight)
                        .overlay {
                            NativeProgressIndicator(size: .small)
                                .frame(width: 16, height: 16)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: previewWidth, height: previewHeight)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "display")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                                Text("No Image")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            }

            // Screen info
            VStack(spacing: 3) {
                Text(screenInfo.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
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
            .frame(width: previewWidth)
        }
        .frame(width: previewWidth + 20) // padding included
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isInteractive ? (isHovered ? Color.accentColor : Color.accentColor.opacity(0.4)) : Color.gray.opacity(0.2),
                    lineWidth: isHovered ? 2 : 1
                )
        )
        .scaleEffect(isHovered && isInteractive ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered && isInteractive ? 0.15 : 0), radius: 8, x: 0, y: 4)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
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
    let availableScreens: [(id: ScreenID, screen: NSScreen, displayName: String)]
    let useSameWallpaperOnAllMonitors: Bool
    let cacheService: ImageCacheService
    let onWallpaperSelected: (ImageFile, NSScreen?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreen: NSScreen?
    @State private var searchText = ""
    @State private var previewImages: [URL: NSImage] = [:]
    @State private var loadedFromCache = false

    private var filteredImages: [ImageFile] {
        if searchText.isEmpty {
            return images
        } else {
            return images.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                if useSameWallpaperOnAllMonitors {
                    Text("Choose wallpaper for all screens")
                        .font(.headline)
                } else {
                    HStack {
                        Text("Choose wallpaper for:")
                            .font(.headline)

                        Picker("Target Screen", selection: $selectedScreen) {
                            Text("All Screens").tag(nil as NSScreen?)
                            ForEach(availableScreens, id: \.id) { screenInfo in
                                Text(screenInfo.displayName).tag(screenInfo.screen as NSScreen?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
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

            Divider()

            // Gallery Grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(filteredImages, id: \.url) { imageFile in
                        WallpaperThumbnail(
                            imageFile: imageFile,
                            previewImage: previewImages[imageFile.url],
                            onTapped: {
                                // If useSameWallpaperOnAllMonitors is true, apply to all screens (nil)
                                // Otherwise, use selectedScreen (nil means All Screens was selected in picker)
                                let finalScreen: NSScreen? = useSameWallpaperOnAllMonitors ? nil : selectedScreen
                                onWallpaperSelected(imageFile, finalScreen)
                            }
                        )
                        .task {
                            await loadThumbnail(for: imageFile)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer with Cancel button
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 550, idealHeight: 600)
        .task {
            // Pre-populate from cache before cells render
            await loadCachedThumbnails()
        }
        .onAppear {
            selectedScreen = targetScreen
        }
    }

    /// Load any previously cached thumbnails for instant display
    private func loadCachedThumbnails() async {
        var cached: [URL: NSImage] = [:]
        for imageFile in images {
            if let thumbnail = cacheService.getCachedThumbnail(for: imageFile.url) {
                cached[imageFile.url] = thumbnail
            }
        }
        if !cached.isEmpty {
            // Update all at once to minimize re-renders
            previewImages = cached
        }
        loadedFromCache = true
    }

    /// Load thumbnail using cache service (will cache for future opens)
    private func loadThumbnail(for imageFile: ImageFile) async {
        // Skip if already loaded
        guard previewImages[imageFile.url] == nil else { return }

        // Check cache service directly to avoid race condition
        if let cached = cacheService.getCachedThumbnail(for: imageFile.url) {
            previewImages[imageFile.url] = cached
            return
        }

        // Load from disk and cache for next time
        let thumbnail = await cacheService.loadThumbnail(from: imageFile.url, maxSize: 150)
        previewImages[imageFile.url] = thumbnail
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
                        .fill(.regularMaterial)
                        .frame(width: 120, height: 80)
                        .overlay {
                            NativeProgressIndicator(size: .small)
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

#Preview {
    ContentView()
        .environmentObject(WallpaperViewModel())
        .environmentObject(SettingsViewModel(settings: WallpaperSettings()))
}
