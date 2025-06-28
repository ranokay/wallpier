//
//  WallpaperService.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import AppKit
import OSLog
import Combine

/// Errors that can occur when setting wallpapers
enum WallpaperError: LocalizedError {
    case permissionDenied
    case invalidImageFormat
    case folderNotFound
    case systemIntegrationFailed
    case fileNotFound
    case unsupportedImageType
    case setWallpaperFailed(Error)

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
        case .setWallpaperFailed(let error):
            return "Failed to set wallpaper: \(error.localizedDescription)"
        }
    }
}

/// Protocol for wallpaper service operations
@preconcurrency protocol WallpaperServiceProtocol: Sendable {
    func setWallpaper(_ imageURL: URL) async throws
    func setWallpaper(_ imageURL: URL, multiMonitorSettings: MultiMonitorSettings) async throws
    func setWallpaperForMultipleMonitors(_ imageURLs: [URL], multiMonitorSettings: MultiMonitorSettings) async throws
    func getCurrentWallpaper() async -> URL?
    func getCurrentWallpapers() async -> [NSScreen: URL]
    func getSupportedImageTypes() async -> [String]
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen?) async throws
    var wallpaperPublisher: AnyPublisher<URL?, Never> { get }
}

/// Service responsible for setting desktop wallpapers
@MainActor
@preconcurrency final class WallpaperService: WallpaperServiceProtocol {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "WallpaperService")
    private let workspace = NSWorkspace.shared

    /// Supported image file extensions
    private let supportedImageTypes = ["jpg", "jpeg", "png", "heic", "bmp", "tiff", "gif"]

    /// Current wallpapers per screen for multi-monitor support
    private var currentWallpapers: [NSScreen: URL] = [:]

    private let wallpaperDidChangePublisher = PassthroughSubject<URL?, Never>()

    var wallpaperPublisher: AnyPublisher<URL?, Never> {
        wallpaperDidChangePublisher.eraseToAnyPublisher()
    }

    init() {
        // No system notification exists for wallpaper changes; polling is required if you want to detect changes.
        // NSWorkspace.shared.notificationCenter.addObserver(
        //     self,
        //     selector: #selector(wallpaperDidChange),
        //     name: NSWorkspace.didChangeDesktopImageNotification,
        //     object: nil
        // )
    }

    /// Sets wallpaper for all screens (legacy method)
    func setWallpaper(_ imageURL: URL) async throws {
        // Default to using same wallpaper on all monitors
        let defaultSettings = MultiMonitorSettings()
        try await setWallpaper(imageURL, multiMonitorSettings: defaultSettings)
    }

    /// Sets wallpaper with multi-monitor support
    func setWallpaper(_ imageURL: URL, multiMonitorSettings: MultiMonitorSettings) async throws {
        logger.info("Setting wallpaper with multi-monitor settings: \(imageURL.path)")

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

        let screens = NSScreen.screens

        if multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Set same wallpaper on all screens
            for screen in screens {
                try await setWallpaperForScreen(imageURL, screen: screen)
                currentWallpapers[screen] = imageURL
            }
        } else {
            // For the first screen, use the provided image
            if let mainScreen = screens.first {
                try await setWallpaperForScreen(imageURL, screen: mainScreen)
                currentWallpapers[mainScreen] = imageURL
            }
            // Other screens keep their current wallpapers or use default if not set
        }

        logger.info("Successfully set wallpaper for \(screens.count) screen(s)")
    }

    /// Sets different wallpapers for multiple monitors
    func setWallpaperForMultipleMonitors(_ imageURLs: [URL], multiMonitorSettings: MultiMonitorSettings) async throws {
        logger.info("Setting multiple wallpapers for monitors: \(imageURLs.count) images")

        let screens = NSScreen.screens

        // Validate all files exist
        for imageURL in imageURLs {
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                logger.error("File not found: \(imageURL.path)")
                throw WallpaperError.fileNotFound
            }

            guard isValidImageType(imageURL) else {
                logger.error("Unsupported image type: \(imageURL.pathExtension)")
                throw WallpaperError.unsupportedImageType
            }
        }

        if multiMonitorSettings.useSameWallpaperOnAllMonitors && !imageURLs.isEmpty {
            // Use first image for all screens
            let imageURL = imageURLs[0]
            for screen in screens {
                try await setWallpaperForScreen(imageURL, screen: screen)
                currentWallpapers[screen] = imageURL
            }
        } else {
            // Set different wallpapers per screen
            for (index, screen) in screens.enumerated() {
                let imageIndex = index % imageURLs.count // Cycle through images if more screens than images
                let imageURL = imageURLs[imageIndex]
                try await setWallpaperForScreen(imageURL, screen: screen)
                currentWallpapers[screen] = imageURL
            }
        }

        logger.info("Successfully set wallpapers for \(screens.count) screen(s)")
    }

    /// Sets wallpaper for a specific screen
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
                do {
                    // Create options dictionary with proper types for Objective-C compatibility
                    let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                        .allowClipping: true,
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue
                    ]

                    try self.workspace.setDesktopImageURL(imageURL, for: targetScreen, options: options)
                    self.logger.info("Successfully set wallpaper for screen \(targetScreen.localizedName)")
                    self.wallpaperDidChangePublisher.send(imageURL)
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to set wallpaper for screen \(targetScreen.localizedName): \(error.localizedDescription)")
                    continuation.resume(throwing: WallpaperError.setWallpaperFailed(error))
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

    /// Gets current wallpapers for all screens
    func getCurrentWallpapers() async -> [NSScreen: URL] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var wallpapers: [NSScreen: URL] = [:]
                for screen in NSScreen.screens {
                    if let url = self.workspace.desktopImageURL(for: screen) {
                        wallpapers[screen] = url
                    }
                }
                continuation.resume(returning: wallpapers)
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

    /// Gets available screens info for multi-monitor setup
    func getScreensInfo() -> [(screen: NSScreen, displayName: String)] {
        return NSScreen.screens.enumerated().map { index, screen in
            let displayName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            return (screen: screen, displayName: displayName)
        }
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