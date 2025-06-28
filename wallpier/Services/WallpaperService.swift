//
//  WallpaperService.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import AppKit
import OSLog

/// Errors that can occur when setting wallpapers
enum WallpaperError: LocalizedError {
    case permissionDenied
    case invalidImageFormat
    case folderNotFound
    case systemIntegrationFailed
    case fileNotFound
    case unsupportedImageType

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission denied to set wallpaper. Please grant necessary permissions."
        case .invalidImageFormat:
            return "The selected image format is not supported."
        case .folderNotFound:
            return "The specified folder could not be found."
        case .systemIntegrationFailed:
            return "Failed to integrate with system wallpaper settings."
        case .fileNotFound:
            return "The specified image file could not be found."
        case .unsupportedImageType:
            return "This image type is not supported for wallpapers."
        }
    }
}

/// Protocol for wallpaper service operations
protocol WallpaperServiceProtocol {
    func setWallpaper(_ imageURL: URL) async throws
    func getCurrentWallpaper() async -> URL?
    func getSupportedImageTypes() async -> [String]
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen?) async throws
}

/// Service responsible for setting desktop wallpapers
@MainActor
@preconcurrency final class WallpaperService: WallpaperServiceProtocol {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "WallpaperService")
    private let workspace = NSWorkspace.shared

    /// Supported image file extensions
    private let supportedImageTypes = ["jpg", "jpeg", "png", "heic", "bmp", "tiff", "gif"]

    /// Sets wallpaper for all screens
    func setWallpaper(_ imageURL: URL) async throws {
        logger.info("Setting wallpaper: \(imageURL.path)")

        // Validate file exists
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            logger.error("File not found: \(imageURL.path)")
            throw WallpaperError.fileNotFound
        }

        // Validate image type
        guard isValidImageType(imageURL) else {
            logger.error("Unsupported image type: \(imageURL.pathExtension)")
            throw WallpaperError.unsupportedImageType
        }

        // Set wallpaper for all screens
        let screens = NSScreen.screens

        for screen in screens {
            try await setWallpaperForScreen(imageURL, screen: screen)
        }

        logger.info("Successfully set wallpaper for \(screens.count) screen(s)")
    }

    /// Sets wallpaper for a specific screen
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                do {
                    let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!

                    // Create options dictionary with proper types for Objective-C compatibility
                    let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                        .allowClipping: true,
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue
                    ]

                    try self.workspace.setDesktopImageURL(imageURL, for: targetScreen, options: options)
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to set wallpaper: \(error.localizedDescription)")
                    continuation.resume(throwing: WallpaperError.systemIntegrationFailed)
                }
            }
        }
    }

    /// Gets the current wallpaper URL for the main screen
    func getCurrentWallpaper() async -> URL? {
        guard let mainScreen = NSScreen.main else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let url = self.workspace.desktopImageURL(for: mainScreen)
                continuation.resume(returning: url)
            }
        }
    }

    /// Returns the list of supported image file extensions
    func getSupportedImageTypes() async -> [String] {
        return supportedImageTypes
    }

    /// Validates if the file type is supported for wallpapers
    private func isValidImageType(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return supportedImageTypes.contains(fileExtension)
    }
}

/// Performance logging utility
extension WallpaperService {
    func logPerformance<T>(_ operation: String, _ block: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("\(operation) took \(String(format: "%.3f", timeElapsed)) seconds")
        return result
    }
}