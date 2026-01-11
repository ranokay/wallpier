//
//  WallpaperThumbnail.swift
//  wallpier
//
//  Individual wallpaper thumbnail component for gallery
//

import SwiftUI

/// Individual wallpaper thumbnail in the gallery
struct WallpaperThumbnail: View {
    let imageFile: ImageFile
    let previewImage: NSImage?
    let onTapped: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Thumbnail
            Group {
                if let nsImage = previewImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 80)
                        .clipped()
                        .cornerRadius(Spacing.cornerRadiusMedium)
                } else {
                    RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                        .fill(.regularMaterial)
                        .frame(width: 120, height: 80)
                        .overlay {
                            NativeProgressIndicator(size: .small)
                                .frame(width: 16, height: 16)
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .stroke(AppColors.primary, lineWidth: isHovered ? 2 : 0)
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(Animations.fastEaseOut, value: isHovered)

            // Name
            Text(imageFile.name)
                .captionStyle()
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
        .help("Click to set as wallpaper")
    }
}
