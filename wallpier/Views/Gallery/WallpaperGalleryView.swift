//
//  WallpaperGalleryView.swift
//  wallpier
//
//  Gallery view for browsing and selecting wallpapers
//

import SwiftUI

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
            VStack(spacing: Spacing.md) {
                if useSameWallpaperOnAllMonitors {
                    Text("Choose wallpaper for all screens")
                        .headlineStyle()
                } else {
                    HStack {
                        Text("Choose wallpaper for:")
                            .headlineStyle()

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
                        .foregroundColor(AppColors.contentSecondary)
                    TextField("Search wallpapers...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(Spacing.lg)

            Divider()

            // Gallery Grid
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 4),
                    spacing: Spacing.md
                ) {
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
                .padding(Spacing.lg)
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
            .padding(Spacing.lg)
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

    // MARK: - Private Methods

    /// Load any previously cached thumbnails for instant display
    private func loadCachedThumbnails() async {
        var cached: [URL: NSImage] = [:]

        // First pass: check memory cache for instant display
        for imageFile in images {
            if let thumbnail = cacheService.getCachedThumbnail(for: imageFile.url) {
                cached[imageFile.url] = thumbnail
            }
        }

        if !cached.isEmpty {
            // Update all at once to minimize re-renders
            previewImages = cached
        }

        // Second pass: load from disk cache (much faster than generating)
        for imageFile in images {
            // Skip if already loaded from memory cache
            guard previewImages[imageFile.url] == nil else { continue }

            if let diskThumbnail = await cacheService.getThumbnailFromDisk(for: imageFile.url, modificationDate: imageFile.modificationDate) {
                previewImages[imageFile.url] = diskThumbnail
            }
        }

        loadedFromCache = true
    }

    /// Load thumbnail using cache service (will cache for future opens)
    private func loadThumbnail(for imageFile: ImageFile) async {
        // Skip if already loaded
        guard previewImages[imageFile.url] == nil else { return }

        // Try disk cache first (much faster than generating)
        if let diskThumbnail = await cacheService.getThumbnailFromDisk(for: imageFile.url, modificationDate: imageFile.modificationDate) {
            previewImages[imageFile.url] = diskThumbnail
            return
        }

        // Fall back to loading and generating (will be cached to disk automatically)
        let thumbnail = await cacheService.loadThumbnail(from: imageFile.url, maxSize: 150)
        previewImages[imageFile.url] = thumbnail
    }
}
