//
//  SettingsViewModel.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import Combine
import AppKit
import OSLog

/// View model for managing application settings
@MainActor
final class SettingsViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "SettingsViewModel")

    // MARK: - Published Properties

    /// Current settings (working copy)
    @Published var settings: WallpaperSettings

    /// Whether settings have been modified
    @Published var hasUnsavedChanges: Bool = false

    /// Current validation errors
    @Published var validationErrors: [String] = []

    /// Whether a folder selection dialog is open
    @Published var isFolderSelectionOpen: Bool = false

    /// Status message for settings operations
    @Published var statusMessage: String = ""

    /// Whether settings are being saved
    @Published var isSaving: Bool = false

    // MARK: - Internal State

    private let originalSettings: WallpaperSettings
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks

    /// Callback for when settings are saved
    var onSettingsSaved: ((WallpaperSettings) -> Void)?

    /// Callback for when settings are cancelled
    var onSettingsCancelled: (() -> Void)?

    // MARK: - Initialization

    init(settings: WallpaperSettings) {
        self.originalSettings = settings
        self.settings = settings

        setupBindings()
        validateSettings()

        logger.info("SettingsViewModel initialized")
    }

    // MARK: - Public Interface

    /// Opens a folder selection dialog
    func selectFolder() {
        logger.info("Opening folder selection dialog")

        isFolderSelectionOpen = true

        let openPanel = NSOpenPanel()
        openPanel.title = "Select Wallpaper Folder"
        openPanel.message = "Choose a folder containing wallpaper images"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = false

        // Set initial directory
        if let currentFolder = settings.folderPath {
            openPanel.directoryURL = currentFolder
        } else {
            openPanel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        }

        openPanel.begin { [weak self] result in
            DispatchQueue.main.async {
                self?.isFolderSelectionOpen = false

                if result == .OK, let selectedURL = openPanel.url {
                    self?.handleFolderSelection(selectedURL)
                }
            }
        }
    }

    /// Saves the current settings
    func saveSettings() {
        logger.info("Saving settings")

        // Validate before saving
        validateSettings()

        guard validationErrors.isEmpty else {
            logger.warning("Cannot save settings - validation errors exist")
            statusMessage = "Please fix validation errors before saving"
            return
        }

        isSaving = true
        statusMessage = "Saving settings..."

        // Save to UserDefaults
        settings.save()

        // Notify callback
        onSettingsSaved?(settings)

        hasUnsavedChanges = false
        isSaving = false
        statusMessage = "Settings saved successfully"

        logger.info("Settings saved successfully")

        // Clear status message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.statusMessage = ""
        }
    }

    /// Discards changes and reverts to original settings
    func cancelChanges() {
        logger.info("Cancelling settings changes")

        settings = originalSettings
        hasUnsavedChanges = false
        validationErrors = []
        statusMessage = ""

        onSettingsCancelled?()

        logger.info("Settings changes cancelled")
    }

    /// Resets settings to defaults
    func resetToDefaults() {
        logger.info("Resetting settings to defaults")

        settings = WallpaperSettings()
        hasUnsavedChanges = true
        validateSettings()
        statusMessage = "Settings reset to defaults"

        logger.info("Settings reset to defaults")
    }

    /// Updates the cycling interval
    func updateCyclingInterval(_ interval: TimeInterval) {
        settings.cyclingInterval = interval
        validateSettings()
    }

    /// Updates the scaling mode
    func updateScalingMode(_ mode: WallpaperScalingMode) {
        settings.scalingMode = mode
    }

    /// Updates the sort order
    func updateSortOrder(_ order: ImageSortOrder) {
        settings.sortOrder = order
    }

    /// Toggles a boolean setting
    func toggleSetting(keyPath: WritableKeyPath<WallpaperSettings, Bool>) {
        settings[keyPath: keyPath].toggle()
    }

    /// Updates file filters
    func updateFileFilters(_ filters: FileFilters) {
        settings.fileFilters = filters
        validateSettings()
    }

    /// Updates multi-monitor settings
    func updateMultiMonitorSettings(_ multiSettings: MultiMonitorSettings) {
        settings.multiMonitorSettings = multiSettings
    }

    /// Updates advanced settings
    func updateAdvancedSettings(_ advanced: AdvancedSettings) {
        settings.advancedSettings = advanced
        validateSettings()
    }

    /// Validates folder path and shows info
    func validateFolderPath() -> (isValid: Bool, info: String) {
        guard let folderPath = settings.folderPath else {
            return (false, "No folder selected")
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: folderPath.path) else {
            return (false, "Folder does not exist")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return (false, "Path is not a directory")
        }

        // Count supported image files
        do {
            let contents = try fileManager.contentsOfDirectory(at: folderPath,
                                                             includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: [.skipsHiddenFiles])

            let supportedExtensions = Set(settings.fileFilters.supportedExtensions)
            let imageCount = contents.filter { url in
                supportedExtensions.contains(url.pathExtension.lowercased())
            }.count

            return (true, "Valid folder with \(imageCount) supported image(s)")

        } catch {
            return (false, "Cannot read folder contents: \(error.localizedDescription)")
        }
    }
}

// MARK: - Private Implementation

private extension SettingsViewModel {
    /// Sets up Combine bindings for reactive updates
    func setupBindings() {
        // Monitor settings changes
        $settings
            .dropFirst() // Skip initial value
            .sink { [weak self] _ in
                self?.hasUnsavedChanges = true
                self?.validateSettings()
            }
            .store(in: &cancellables)
    }

    /// Handles folder selection from the open panel
    func handleFolderSelection(_ url: URL) {
        logger.info("Folder selected: \(url.path)")

        // Check if we can access the folder
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("Selected folder does not exist: \(url.path)")
            statusMessage = "Selected folder does not exist"
            return
        }

        // Update settings - even if it's the same folder, we want to trigger updates
        let oldPath = settings.folderPath
        settings.folderPath = url

        // Force trigger settings update even if the path is the same
        if oldPath == url {
            // Manually trigger the onSettingsSaved callback to ensure UI updates
            onSettingsSaved?(settings)
        }

        // Save settings immediately
        settings.save()

        statusMessage = "Folder selected: \(url.lastPathComponent)"

        // Clear status message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.statusMessage = ""
        }

        logger.info("Folder selection completed")
    }

    /// Validates current settings and updates validation errors
    func validateSettings() {
        validationErrors = settings.validate()

        // Additional UI-specific validations
        if settings.advancedSettings.maxCacheSizeMB < 10 {
            validationErrors.append("Cache size must be at least 10 MB")
        }

        if settings.advancedSettings.maxCacheSizeMB > 1000 {
            validationErrors.append("Cache size cannot exceed 1000 MB")
        }

        if settings.advancedSettings.maxCachedImages < 1 {
            validationErrors.append("Must cache at least 1 image")
        }

        if settings.advancedSettings.maxCachedImages > 100 {
            validationErrors.append("Cannot cache more than 100 images")
        }
    }
}

// MARK: - Convenience Properties

extension SettingsViewModel {
    /// Whether the settings can be saved
    var canSave: Bool {
        return hasUnsavedChanges && validationErrors.isEmpty && !isSaving
    }

    /// Whether the settings have any issues
    var hasIssues: Bool {
        return !validationErrors.isEmpty
    }

    /// Current folder display name
    var folderDisplayName: String {
        guard let folderPath = settings.folderPath else {
            return "No folder selected"
        }
        return folderPath.lastPathComponent
    }

    /// Full folder path for display
    var folderFullPath: String {
        guard let folderPath = settings.folderPath else {
            return "No folder selected"
        }
        return folderPath.path
    }

    /// Available cycling intervals for picker
    var availableIntervals: [(name: String, seconds: TimeInterval)] {
        return WallpaperSettings.commonIntervals
    }

    /// Current interval display name
    var currentIntervalName: String {
        let currentInterval = settings.cyclingInterval

        if let match = availableIntervals.first(where: { $0.seconds == currentInterval }) {
            return match.name
        }

        return settings.cyclingIntervalDescription
    }

    /// Whether advanced settings are recommended
    var shouldShowAdvancedWarning: Bool {
        return settings.advancedSettings.enableDetailedLogging ||
               settings.advancedSettings.maxCacheSizeMB > 200 ||
               !settings.advancedSettings.pauseInLowPowerMode
    }
}

// MARK: - Helper Methods

extension SettingsViewModel {
    /// Gets system recommendations for settings
    func getSystemRecommendations() -> [String] {
        var recommendations: [String] = []

        // Performance recommendations
        if settings.cyclingInterval < 60 {
            recommendations.append("Consider increasing cycling interval to reduce system load")
        }

        if settings.advancedSettings.maxCacheSizeMB > 200 {
            recommendations.append("Large cache size may impact system memory")
        }

        if !settings.advancedSettings.pauseInLowPowerMode {
            recommendations.append("Enable 'Pause in Low Power Mode' to save battery")
        }

        // Feature recommendations
        if !settings.isRecursiveScanEnabled {
            recommendations.append("Enable recursive scanning to find images in subfolders")
        }

        if !settings.advancedSettings.preloadNextImage {
            recommendations.append("Enable image preloading for smoother transitions")
        }

        return recommendations
    }

    /// Exports settings to a file
    func exportSettings() -> URL? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(settings)

            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsURL.appendingPathComponent("wallpier-settings.json")

            try data.write(to: fileURL)

            logger.info("Settings exported to: \(fileURL.path)")
            return fileURL

        } catch {
            logger.error("Failed to export settings: \(error.localizedDescription)")
            return nil
        }
    }

    /// Imports settings from a file
    func importSettings(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let importedSettings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

            settings = importedSettings
            statusMessage = "Settings imported successfully"

            logger.info("Settings imported from: \(url.path)")
            return true

        } catch {
            logger.error("Failed to import settings: \(error.localizedDescription)")
            statusMessage = "Failed to import settings: \(error.localizedDescription)"
            return false
        }
    }
}