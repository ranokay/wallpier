//
//  Protocols.swift
//  wallpier
//
//  Consolidated service protocols for dependency injection and testing
//

import Foundation
import AppKit
import Combine

// MARK: - Image Cache Service Protocol

/// Protocol for image caching operations
@preconcurrency
@MainActor
protocol ImageCacheServiceProtocol: Sendable {
    /// Cache an image for a given URL
    func cacheImage(_ image: NSImage, for url: URL) async

    /// Retrieve a cached image for a URL
    func getCachedImage(for url: URL) async -> NSImage?

    /// Preload an image from URL into cache
    func preloadImage(from url: URL) async -> NSImage?

    /// Clear all cached images
    func clearCache() async

    /// Remove a specific cached image
    func removeCachedImage(for url: URL) async

    /// Get the current cache size in bytes
    func getCacheSize() async -> Int

    /// Preload multiple images with specified priority
    func preloadImages(_ urls: [URL], priority: TaskPriority) async

    /// Optimize cache by removing least-used entries
    func optimizeCache() async

    /// Cache a thumbnail for a given URL (persists across gallery opens)
    func cacheThumbnail(_ image: NSImage, for url: URL, size: CGFloat) async

    /// Retrieve a cached thumbnail for a URL
    func getCachedThumbnail(for url: URL) async -> NSImage?

    /// Load or create a thumbnail, using cache if available
    func loadThumbnail(from url: URL, maxSize: CGFloat) async -> NSImage?
}

// MARK: - Image Scanner Service Protocol

/// Protocol for image scanning operations
protocol ImageScannerServiceProtocol {
    /// Scan a directory for image files (non-recursive)
    func scanDirectory(_ url: URL) async throws -> [ImageFile]

    /// Scan a directory recursively for image files with progress callback
    func scanDirectoryRecursively(_ url: URL, progress: @escaping (Int) -> Void) async throws -> [ImageFile]

    /// Validate if a file is a supported image format
    func validateImageFile(_ url: URL) -> Bool

    /// Quick scan with limited depth for faster results
    func quickScanDirectory(_ url: URL, maxDepth: Int) async throws -> [ImageFile]
}

// MARK: - Wallpaper Service Protocol

/// Protocol for wallpaper service operations
@preconcurrency
@MainActor
protocol WallpaperServiceProtocol: Sendable {
    /// Set wallpaper for all screens
    func setWallpaper(_ imageURL: URL) async throws

    /// Set wallpaper with multi-monitor settings
    func setWallpaper(_ imageURL: URL, multiMonitorSettings: MultiMonitorSettings, defaultScalingMode: WallpaperScalingMode) async throws

    /// Set different wallpapers for multiple monitors
    func setWallpaperForMultipleMonitors(_ imageURLs: [URL], multiMonitorSettings: MultiMonitorSettings, defaultScalingMode: WallpaperScalingMode) async throws

    /// Get the current wallpaper URL for the main screen
    func getCurrentWallpaper() async -> URL?

    /// Get current wallpapers for all screens
    func getCurrentWallpapers() async -> [NSScreen: URL]

    /// Get list of supported image file types
    func getSupportedImageTypes() async -> [String]

    /// Set wallpaper for a specific screen
    func setWallpaperForScreen(_ imageURL: URL, screen: NSScreen?) async throws

    /// Publisher for wallpaper changes
    var wallpaperPublisher: AnyPublisher<URL?, Never> { get }
}

// MARK: - System Service Protocol

/// Protocol defining system integration capabilities
@MainActor
protocol SystemServiceProtocol: Sendable {
    /// Request necessary permissions for the app
    func requestPermissions() async -> Bool

    /// Check if launch at startup is enabled
    var isLaunchAtStartupEnabled: Bool { get }

    /// Enable or disable launch at startup
    func setLaunchAtStartup(_ enabled: Bool) async -> Bool

    /// Check current permission status
    func checkPermissionStatus() -> PermissionStatus

    /// Hide dock icon for menu bar only operation
    func configureDockVisibility(_ visible: Bool)

    /// Handle app state changes
    func handleAppStateChange(_ state: AppState)
}

// MARK: - File Monitor Service Protocol

/// Protocol for file monitoring operations
protocol FileMonitorServiceProtocol {
    /// Start monitoring a directory for changes
    func startMonitoring(_ url: URL, callback: @escaping () -> Void) throws

    /// Stop all file monitoring
    func stopMonitoring()

    /// Check if currently monitoring a directory
    func isMonitoring() -> Bool
}

/// Delegate protocol for file monitor events
protocol FileMonitorDelegate: AnyObject {
    /// Called when changes are detected in the monitored directory
    func fileMonitorDidDetectChanges(_ monitor: FileMonitorService, in directory: URL) async

    /// Called when monitoring fails with an error
    func fileMonitorDidFailWithError(_ monitor: FileMonitorService, error: Error) async
}
