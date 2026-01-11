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
    private let logger = Logger.wallpaper
    private let workspace = NSWorkspace.shared

    /// Supported image file extensions
    private let supportedImageTypes = ["jpg", "jpeg", "png", "heic", "bmp", "tiff", "gif", "webp"]

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
        try await setWallpaper(imageURL, multiMonitorSettings: defaultSettings, defaultScalingMode: .fill)
    }

    /// Sets wallpaper with multi-monitor support and scaling preferences
    func setWallpaper(_ imageURL: URL, multiMonitorSettings: MultiMonitorSettings, defaultScalingMode: WallpaperScalingMode) async throws {
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

        let start = CFAbsoluteTimeGetCurrent()

        if multiMonitorSettings.useSameWallpaperOnAllMonitors {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, screen) in screens.enumerated() {
                    group.addTask {
                        let displayName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
                        let scalingMode = Self.resolvedScalingMode(for: displayName, settings: multiMonitorSettings, defaultScalingMode: defaultScalingMode)
                        let options = Self.desktopOptions(for: scalingMode)
                        try await self.setWallpaperForScreen(imageURL, screen: screen, options: options)
                    }
                }

                try await group.waitForAll()
            }
        } else if let mainScreen = screens.first {
            let displayName = mainScreen.localizedName.isEmpty ? "Display 1" : mainScreen.localizedName
            let scalingMode = Self.resolvedScalingMode(for: displayName, settings: multiMonitorSettings, defaultScalingMode: defaultScalingMode)
            let options = Self.desktopOptions(for: scalingMode)
            try await setWallpaperForScreen(imageURL, screen: mainScreen, options: options)
            logger.debug("Multi-monitor mode: updated main screen only, preserving others")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info("Successfully set wallpaper for \(screens.count) screen(s) in \(String(format: "%.3f", elapsed))s")
    }

    /// Sets different wallpapers for multiple monitors
    func setWallpaperForMultipleMonitors(_ imageURLs: [URL], multiMonitorSettings: MultiMonitorSettings, defaultScalingMode: WallpaperScalingMode) async throws {
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
            // Use first image for all screens with per-monitor scaling (parallel execution)
            let imageURL = imageURLs[0]
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, screen) in screens.enumerated() {
                    group.addTask {
                        let displayName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
                        let scalingMode = Self.resolvedScalingMode(for: displayName, settings: multiMonitorSettings, defaultScalingMode: defaultScalingMode)
                        let options = Self.desktopOptions(for: scalingMode)
                        try await self.setWallpaperForScreen(imageURL, screen: screen, options: options)
                    }
                }

                // Wait for all screens to complete
                try await group.waitForAll()
            }
        } else {
            // Set different wallpapers per screen with per-monitor scaling (parallel execution)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, screen) in screens.enumerated() {
                    group.addTask {
                        let imageIndex = index % imageURLs.count // Cycle through images if more screens than images
                        let imageURL = imageURLs[imageIndex]
                        let displayName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
                        let scalingMode = Self.resolvedScalingMode(for: displayName, settings: multiMonitorSettings, defaultScalingMode: defaultScalingMode)
                        let options = Self.desktopOptions(for: scalingMode)
                        try await self.setWallpaperForScreen(imageURL, screen: screen, options: options)
                    }
                }

                // Wait for all screens to complete
                try await group.waitForAll()
            }
        }

        logger.info("Successfully set wallpapers for \(screens.count) screen(s) in parallel")
    }

    /// Sets wallpaper for a specific screen
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen? = nil) async throws {
        let defaultOptions = Self.desktopOptions(for: .fill)
        try await setWallpaperForScreen(imageURL, screen: screen, options: defaultOptions)
    }

    /// Sets wallpaper for a specific screen with custom options
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen? = nil, options: [NSWorkspace.DesktopImageOptionKey: Any]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                guard let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first else {
                    self.logger.error("No available screens found")
                    continuation.resume(throwing: WallpaperError.noAvailableScreens)
                    return
                }

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
        return workspace.desktopImageURL(for: mainScreen)
    }

    /// Gets current wallpapers for all screens
    func getCurrentWallpapers() async -> [NSScreen: URL] {
        var wallpapers: [NSScreen: URL] = [:]
        for screen in NSScreen.screens {
            if let url = workspace.desktopImageURL(for: screen) {
                wallpapers[screen] = url
            }
        }
        return wallpapers
    }

    /// Returns the list of supported image file extensions
    func getSupportedImageTypes() async -> [String] {
        return supportedImageTypes
    }

    /// Validates if the file type is supported for wallpapers
    nonisolated private func isValidImageType(_ url: URL) -> Bool {
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

// MARK: - Desktop Options

extension WallpaperService {
    /// Resolves per-monitor scaling preference falling back to default
    nonisolated static func resolvedScalingMode(for displayName: String, settings: MultiMonitorSettings, defaultScalingMode: WallpaperScalingMode) -> WallpaperScalingMode {
        settings.perMonitorScaling[displayName] ?? defaultScalingMode
    }

    /// Nonisolated helper so callers in concurrent task groups avoid MainActor hops
    nonisolated static func desktopOptions(for scalingMode: WallpaperScalingMode) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: scalingMode.nsImageScaling.rawValue
        ]

        switch scalingMode {
        case .tile:
            options[.allowClipping] = false
            options[.fillColor] = NSColor.black
        case .center:
            options[.allowClipping] = false
        default:
            options[.allowClipping] = true
        }

        return options
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