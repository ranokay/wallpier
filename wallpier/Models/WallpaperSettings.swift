//
//  WallpaperSettings.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import AppKit

/// Image scaling modes for wallpaper display
enum WallpaperScalingMode: String, CaseIterable, Codable {
    case fill = "fill"
    case fit = "fit"
    case stretch = "stretch"
    case center = "center"
    case tile = "tile"

    var displayName: String {
        switch self {
        case .fill:
            return "Fill Screen"
        case .fit:
            return "Fit to Screen"
        case .stretch:
            return "Stretch to Fill"
        case .center:
            return "Center"
        case .tile:
            return "Tile"
        }
    }

    var nsImageScaling: NSImageScaling {
        switch self {
        case .fill:
            return .scaleProportionallyUpOrDown
        case .fit:
            return .scaleProportionallyDown
        case .stretch:
            return .scaleAxesIndependently
        case .center:
            return .scaleNone
        case .tile:
            return .scaleNone // Will be handled separately
        }
    }
}

/// Sort order for image cycling
enum ImageSortOrder: String, CaseIterable, Codable {
    case alphabetical = "alphabetical"
    case dateModified = "dateModified"
    case dateAdded = "dateAdded"
    case fileSize = "fileSize"
    case random = "random"

    var displayName: String {
        switch self {
        case .alphabetical:
            return "Alphabetical"
        case .dateModified:
            return "Date Modified"
        case .dateAdded:
            return "Date Added"
        case .fileSize:
            return "File Size"
        case .random:
            return "Random"
        }
    }
}

/// Main settings structure for the wallpaper application
struct WallpaperSettings: Codable {
    /// Current version of settings for migration
    static let currentVersion = 1
    let version: Int

    /// Selected folder path for wallpaper images
    var folderPath: URL?

    /// Bookmark data for persistent security-scoped access to wallpaper folder
    var folderBookmark: Data?

    /// Whether to scan subfolders recursively
    var isRecursiveScanEnabled: Bool

    /// Cycling interval in seconds
    var cyclingInterval: TimeInterval

    /// Whether automatic cycling is enabled
    var isCyclingEnabled: Bool

    /// Image scaling mode
    var scalingMode: WallpaperScalingMode

    /// Sort order for images
    var sortOrder: ImageSortOrder

    /// Whether to shuffle images
    var isShuffleEnabled: Bool

    /// Whether app should launch at startup
    var launchAtStartup: Bool

    /// Whether to show menu bar icon
    var showMenuBarIcon: Bool



    /// Multi-monitor configuration
    var multiMonitorSettings: MultiMonitorSettings

    /// Image file filters
    var fileFilters: FileFilters

    /// Advanced settings
    var advancedSettings: AdvancedSettings

    /// System integration settings
    var systemIntegration: SystemIntegrationSettings?

    /// Default initializer with sensible defaults
    init() {
        self.version = Self.currentVersion
        self.folderPath = nil
        self.folderBookmark = nil
        self.isRecursiveScanEnabled = true
        self.cyclingInterval = 300 // 5 minutes
        self.isCyclingEnabled = false
        self.scalingMode = .fill
        self.sortOrder = .random
        self.isShuffleEnabled = true
        self.launchAtStartup = false
        self.showMenuBarIcon = true
        self.multiMonitorSettings = MultiMonitorSettings()
        self.fileFilters = FileFilters()
        self.advancedSettings = AdvancedSettings()
        self.systemIntegration = SystemIntegrationSettings()
    }

    /// Validates the current settings
    func validate() -> [String] {
        var errors: [String] = []

        // Validate folder path
        if let folderPath = folderPath {
            if !FileManager.default.fileExists(atPath: folderPath.path) {
                errors.append("Selected folder does not exist: \(folderPath.path)")
            }
        }

        // Validate cycling interval
        if cyclingInterval < 10 {
            errors.append("Cycling interval must be at least 10 seconds")
        }

        if cyclingInterval > 86400 {
            errors.append("Cycling interval cannot exceed 24 hours")
        }

        return errors
    }

    /// Returns user-friendly cycling interval description
    var cyclingIntervalDescription: String {
        if cyclingInterval < 60 {
            return "\(Int(cyclingInterval)) seconds"
        } else if cyclingInterval < 3600 {
            let minutes = Int(cyclingInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = Int(cyclingInterval / 3600)
            let minutes = Int((cyclingInterval.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }
}

/// Multi-monitor specific settings
struct MultiMonitorSettings: Codable {
    /// Whether to use the same wallpaper on all monitors
    var useSameWallpaperOnAllMonitors: Bool

    /// Per-monitor scaling modes (key is monitor identifier)
    var perMonitorScaling: [String: WallpaperScalingMode]

    init() {
        self.useSameWallpaperOnAllMonitors = true
        self.perMonitorScaling = [:]
    }
}

/// File filtering settings
struct FileFilters: Codable {
    /// Minimum file size in bytes (0 = no limit)
    var minimumFileSize: Int

    /// Maximum file size in bytes (0 = no limit)
    var maximumFileSize: Int

    /// Whether to include HEIC files
    var includeHEICFiles: Bool

    /// Whether to include GIF files
    var includeGIFFiles: Bool

    /// Whether to include WebP files
    var includeWebPFiles: Bool

    /// Custom file extensions to include
    var customExtensions: [String]

    init() {
        self.minimumFileSize = 0
        self.maximumFileSize = 0
        self.includeHEICFiles = true
        self.includeGIFFiles = true
        self.includeWebPFiles = true
        self.customExtensions = []
    }

    /// Returns the complete list of supported file extensions
    var supportedExtensions: [String] {
        var extensions = ["jpg", "jpeg", "png", "bmp", "tiff"]

        if includeHEICFiles {
            extensions.append("heic")
        }

        if includeGIFFiles {
            extensions.append("gif")
        }

        if includeWebPFiles {
            extensions.append("webp")
        }

        extensions.append(contentsOf: customExtensions.map { $0.lowercased() })

        return Array(Set(extensions)) // Remove duplicates
    }
}

/// Advanced application settings
struct AdvancedSettings: Codable {
    /// Maximum number of images to cache in memory
    var maxCachedImages: Int

    /// Whether to preload next image for smoother transitions
    var preloadNextImage: Bool

    /// Whether to pause cycling when on battery power
    var pauseOnBattery: Bool

    /// Whether to pause cycling when in low power mode
    var pauseInLowPowerMode: Bool

    /// Whether to enable detailed logging
    var enableDetailedLogging: Bool

    /// Maximum cache size in MB
    var maxCacheSizeMB: Int

    init() {
        self.maxCachedImages = 10
        self.preloadNextImage = true
        self.pauseOnBattery = false
        self.pauseInLowPowerMode = true
        self.enableDetailedLogging = false
        self.maxCacheSizeMB = 100
    }
}

/// System integration settings
struct SystemIntegrationSettings: Codable {
    /// Whether to launch app at system startup
    var launchAtStartup: Bool

    /// Whether to hide dock icon (menu bar only mode)
    var hideDockIcon: Bool

    /// Whether to show launch at startup dialog on first run
    var hasShownStartupDialog: Bool



    /// Whether to pause cycling when screen is locked
    var pauseWhenScreenLocked: Bool

    /// Whether to pause cycling during presentations/fullscreen apps
    var pauseDuringPresentations: Bool

    init() {
        self.launchAtStartup = false
        self.hideDockIcon = false
        self.hasShownStartupDialog = false
        self.pauseWhenScreenLocked = false
        self.pauseDuringPresentations = true
    }
}

// MARK: - UserDefaults Integration

extension WallpaperSettings {
    /// UserDefaults key for settings
    private static let userDefaultsKey = "WallpaperSettings"

    /// Saves settings to UserDefaults
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    /// Loads settings from UserDefaults
    static func load() -> WallpaperSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return WallpaperSettings() // Return defaults
        }

        do {
            let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)
            let migratedSettings = migrateIfNeeded(settings)

            // Validate loaded settings and fix any invalid values
            return validateAndFixSettings(migratedSettings)
        } catch {
            print("Failed to load settings: \(error)")
            return WallpaperSettings() // Return defaults on error
        }
    }

    /// Validates settings and fixes any invalid values
    private static func validateAndFixSettings(_ settings: WallpaperSettings) -> WallpaperSettings {
        var fixedSettings = settings

        // Validate cycling interval
        if !fixedSettings.cyclingInterval.isFinite ||
           fixedSettings.cyclingInterval < 10 ||
           fixedSettings.cyclingInterval > 86400 {
            print("Invalid cycling interval \(fixedSettings.cyclingInterval), resetting to 300")
            fixedSettings.cyclingInterval = 300
        }

        // Validate cache size
        if fixedSettings.advancedSettings.maxCacheSizeMB < 10 ||
           fixedSettings.advancedSettings.maxCacheSizeMB > 1000 {
            print("Invalid cache size \(fixedSettings.advancedSettings.maxCacheSizeMB), resetting to 100")
            fixedSettings.advancedSettings.maxCacheSizeMB = 100
        }

        // Validate cached images count
        if fixedSettings.advancedSettings.maxCachedImages < 1 ||
           fixedSettings.advancedSettings.maxCachedImages > 100 {
            print("Invalid cached images count \(fixedSettings.advancedSettings.maxCachedImages), resetting to 10")
            fixedSettings.advancedSettings.maxCachedImages = 10
        }

        return fixedSettings
    }

    /// Migrates settings between versions
    private static func migrateIfNeeded(_ settings: WallpaperSettings) -> WallpaperSettings {
        if settings.version < currentVersion {
            // Perform migrations here as needed
            var migratedSettings = settings
            migratedSettings = WallpaperSettings() // For now, reset to defaults
            migratedSettings.save()
            return migratedSettings
        }
        return settings
    }

    /// Resets settings to defaults
    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Convenience Extensions

extension WallpaperSettings {
    /// Quick access to common cycling intervals
    static let commonIntervals: [(name: String, seconds: TimeInterval)] = [
        ("10 seconds", 10),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600),
        ("2 hours", 7200),
        ("6 hours", 21600),
        ("12 hours", 43200),
        ("24 hours", 86400)
    ]

    /// Whether the settings are in a valid state to start cycling
    var canStartCycling: Bool {
        guard let folderPath = folderPath else { return false }
        return FileManager.default.fileExists(atPath: folderPath.path) &&
               cyclingInterval >= 10 &&
               validate().isEmpty
    }

    /// Creates a copy with a new folder path
    func withFolderPath(_ path: URL?) -> WallpaperSettings {
        var settings = self
        settings.folderPath = path
        return settings
    }

    /// Creates a copy with cycling enabled/disabled
    func withCycling(_ enabled: Bool) -> WallpaperSettings {
        var settings = self
        settings.isCyclingEnabled = enabled
        return settings
    }
}