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

// Note: WallpaperError is defined in Utilities/Errors.swift as the single source of truth
// Note: WallpaperServiceProtocol is defined in Utilities/Protocols.swift

/// Service responsible for setting desktop wallpapers
@MainActor
@preconcurrency final class WallpaperService: WallpaperServiceProtocol {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "WallpaperService")
    private let workspace = NSWorkspace.shared

    /// Supported image file extensions
    private let supportedImageTypes = ["jpg", "jpeg", "png", "heic", "bmp", "tiff", "gif"]

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
            }
        } else {
            // For the first screen, use the provided image
            if let mainScreen = screens.first {
                try await setWallpaperForScreen(imageURL, screen: mainScreen)
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
            // Use first image for all screens with per-monitor scaling
            let imageURL = imageURLs[0]
            for (index, screen) in screens.enumerated() {
                let displayName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
                let scalingMode = multiMonitorSettings.perMonitorScaling[displayName] ?? .fill
                let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                    .allowClipping: true,
                    .imageScaling: scalingMode.nsImageScaling.rawValue
                ]
                try await setWallpaperForScreen(imageURL, screen: screen, options: options)
            }
        } else {
            // Set different wallpapers per screen with per-monitor scaling
            for (index, screen) in screens.enumerated() {
                let imageIndex = index % imageURLs.count // Cycle through images if more screens than images
                let imageURL = imageURLs[imageIndex]
                let displayName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
                let scalingMode = multiMonitorSettings.perMonitorScaling[displayName] ?? .fill
                let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                    .allowClipping: true,
                    .imageScaling: scalingMode.nsImageScaling.rawValue
                ]
                try await setWallpaperForScreen(imageURL, screen: screen, options: options)
            }
        }

        logger.info("Successfully set wallpapers for \(screens.count) screen(s)")
    }

    /// Sets wallpaper for a specific screen
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen? = nil) async throws {
        // Default options for backward compatibility
        let defaultOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .allowClipping: true,
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue
        ]
        try await setWallpaperForScreen(imageURL, screen: screen, options: defaultOptions)
    }

    /// Sets wallpaper for a specific screen with custom options
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen? = nil, options: [NSWorkspace.DesktopImageOptionKey: Any]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
                do {
                    try self.workspace.setDesktopImageURL(imageURL, for: targetScreen, options: options)
                    self.logger.info("Successfully set wallpaper for screen \(targetScreen.localizedName)")
                    self.wallpaperDidChangePublisher.send(imageURL)
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to set wallpaper for screen \(targetScreen.localizedName): \(error.localizedDescription)")
                    continuation.resume(throwing: WallpaperError.setWallpaperFailed(underlying: error))
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