//
//  ScreenPreviewCard.swift
//  wallpier
//
//  Individual screen preview card for multi-monitor display
//

import SwiftUI

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
        VStack(spacing: Spacing.sm + 2) {
            // Screen preview with fixed 16:10 aspect ratio
            Group {
                if let nsImage = previewImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: previewWidth, height: previewHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium))
                } else if currentImage != nil {
                    RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                        .fill(.regularMaterial)
                        .frame(width: previewWidth, height: previewHeight)
                        .overlay {
                            NativeProgressIndicator(size: .small)
                                .frame(width: 16, height: 16)
                        }
                } else {
                    RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                        .fill(.quaternary)
                        .frame(width: previewWidth, height: previewHeight)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "display")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppColors.contentSecondary)
                                Text("No Image")
                                    .captionStyle()
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
                        .foregroundColor(AppColors.contentSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No wallpaper")
                        .font(.caption2)
                        .foregroundColor(AppColors.contentSecondary)
                }
            }
            .frame(width: previewWidth)
        }
        .frame(width: previewWidth + Spacing.sectionSpacing) // padding included
        .padding(Spacing.sm + 2)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge)
                .strokeBorder(
                    isInteractive
                        ? (isHovered ? AppColors.primary : AppColors.primary.opacity(0.4))
                        : AppColors.border.opacity(0.2),
                    lineWidth: isHovered ? 2 : 1
                )
        )
        .scaleEffect(isHovered && isInteractive ? 1.02 : 1.0)
        .shadow(color: AppColors.shadowMedium.opacity(isHovered && isInteractive ? 1 : 0), radius: 8, x: 0, y: 4)
        .animation(Animations.fastEaseOut, value: isHovered)
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
