//
//  MultiMonitorPreviewView.swift
//  wallpier
//
//  Multi-monitor preview showing current wallpapers for each screen
//

import SwiftUI

/// Multi-monitor preview showing current wallpapers for each screen
struct MultiMonitorPreviewView: View {
    let currentImages: [ScreenID: ImageFile]
    let availableScreens: [(id: ScreenID, screen: NSScreen, displayName: String)]
    let isInteractive: Bool
    let onScreenTapped: ((NSScreen) -> Void)?
    @State private var previewImages: [ScreenID: NSImage?] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Multi-Monitor Wallpapers")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isInteractive {
                    Text("Click to change")
                        .captionStyle()
                }
            }

            // Center the preview cards horizontally
            HStack {
                Spacer()
                if availableScreens.count <= 2 {
                    // Horizontal layout for 1-2 screens
                    HStack(spacing: Spacing.sectionSpacing) {
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
                    LazyVGrid(
                        columns: [GridItem(.fixed(286)), GridItem(.fixed(286))],
                        spacing: Spacing.sectionSpacing
                    ) {
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
