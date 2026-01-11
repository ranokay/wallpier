//
//  ImagePreviewView.swift
//  wallpier
//
//  Optimized image preview component with downscaled loading
//

import SwiftUI

/// Optimized image view with downscaled previews for better performance
struct ImagePreviewView: View {
    let imageFile: ImageFile
    @State private var image: NSImage?
    @State private var isLoaded = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Image Preview
            Group {
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium))
                        .opacity(isLoaded ? 1 : 0)
                } else {
                    RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                        .fill(.regularMaterial)
                        .overlay {
                            NativeProgressIndicator(size: .small)
                                .frame(width: 20, height: 20)
                        }
                }
            }
            .frame(maxHeight: 300)
            .animation(Animations.fastEaseOut, value: isLoaded)

            // Image Info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(imageFile.name)
                    .headlineStyle()
                    .lineLimit(2)

                HStack {
                    Text(imageFile.formattedSize)
                    Spacer()
                    Text(imageFile.modificationDate, style: .date)
                }
                .captionStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium))
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
