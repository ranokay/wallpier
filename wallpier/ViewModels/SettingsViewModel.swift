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

    /// Whether to show a toast notification
    @Published var showToast: Bool = false

    /// Toast message content
    @Published var toastMessage: String = ""

    // MARK: - Internal State

    private var originalSettings: WallpaperSettings
    private var cancellables = Set<AnyCancellable>()

    /// Currently accessed security-scoped URL that needs to be released
    /// Using nonisolated(unsafe) is required here because deinit is nonisolated
    /// and we need to release the security-scoped resource when the object is deallocated
    nonisolated(unsafe) private var currentSecurityScopedURL: URL?

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

        // Restore security-scoped access if bookmark exists
        if let bookmark = settings.folderBookmark {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmark,
                                   options: [.withSecurityScope, .withoutUI],
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale)
                if isStale {
                    logger.warning("Bookmark data is stale for folder: \(url.path)")
                }
                if startAccessingSecurityScopedResource(for: url) {
                    self.settings.folderPath = url
                    self.originalSettings.folderPath = url
                    logger.info("Accessing persisted folder: \(url.path)")
                }
            } catch {
                logger.error("Failed to resolve bookmark for folder: \(error.localizedDescription)")
            }
        }

        logger.info("SettingsViewModel initialized")
    }

    deinit {
        // Safe to call from nonisolated context since currentSecurityScopedURL is nonisolated(unsafe)
        if let currentURL = currentSecurityScopedURL {
            currentURL.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Security-Scoped Resource Management

    /// Stops accessing the current security-scoped resource if one exists
    private func stopAccessingCurrentSecurityScopedResource() {
        if let currentURL = currentSecurityScopedURL {
            currentURL.stopAccessingSecurityScopedResource()
            logger.info("Stopped accessing security-scoped resource: \(currentURL.path)")
            currentSecurityScopedURL = nil
        }
    }

    /// Starts accessing a security-scoped resource, stopping any previous one
    private func startAccessingSecurityScopedResource(for url: URL) -> Bool {
        // Stop accessing any current resource first
        stopAccessingCurrentSecurityScopedResource()

        // Start accessing the new resource
        if url.startAccessingSecurityScopedResource() {
            currentSecurityScopedURL = url
            logger.info("Started accessing security-scoped resource: \(url.path)")
            return true
        } else {
            logger.warning("Failed to access security-scoped resource: \(url.path)")
            return false
        }
    }

    // MARK: - Public Interface

    /// Opens a folder selection dialog (for settings window - requires Save to apply)
    func selectFolder() {
        openFolderSelectionPanel(saveImmediately: false)
    }

    /// Opens a folder selection dialog and saves immediately (for sidebar/quick settings)
    func selectFolderAndSaveImmediately() {
        openFolderSelectionPanel(saveImmediately: true)
    }

    /// Opens the folder selection panel
    private func openFolderSelectionPanel(saveImmediately: Bool) {
        logger.info("Opening folder selection dialog, saveImmediately: \(saveImmediately)")

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
                    self?.handleFolderSelection(selectedURL, saveImmediately: saveImmediately)
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
            showToast(message: "Please fix validation errors before saving")
            return
        }

        isSaving = true

        // Save to UserDefaults
        settings.save()

        // Notify callback
        onSettingsSaved?(settings)

        hasUnsavedChanges = false
        // Update baseline so cancel no longer reverts saved changes
        originalSettings = settings
        isSaving = false

        logger.info("Settings saved successfully")

        // Show success toast
        showToast(message: "Settings saved successfully")
    }

    /// Discards changes and reverts to original settings
    func cancelChanges() {
        // Only cancel if there are unsaved changes
        guard hasUnsavedChanges else { return }
        logger.info("Cancelling settings changes")

        settings = originalSettings
        hasUnsavedChanges = false
        validationErrors = []
        statusMessage = ""

        onSettingsCancelled?()

        logger.info("Settings changes cancelled")
    }

    /// Shows a toast notification to the user
    private func showToast(message: String) {
        toastMessage = message
        showToast = true

        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showToast = false
        }
    }

    /// Resets settings to defaults
    func resetToDefaults() {
        logger.info("Resetting settings to defaults")

        settings = WallpaperSettings()
        hasUnsavedChanges = true
        validateSettings()
        showToast(message: "Settings reset to defaults")

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
        // Monitor settings changes to track modifications
        $settings
            .dropFirst() // Skip initial value
            .sink { [weak self] _ in
                self?.hasUnsavedChanges = true
                self?.validateSettings()
            }
            .store(in: &cancellables)
    }

    /// Handles folder selection from the open panel
    /// - Parameter saveImmediately: If true, saves settings immediately after selection (for sidebar/quick settings)
    func handleFolderSelection(_ url: URL, saveImmediately: Bool = false) {
        logger.info("Folder selected: \(url.path), saveImmediately: \(saveImmediately)")

        // Check if we can access the folder
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("Selected folder does not exist: \(url.path)")
            showToast(message: "Selected folder does not exist")
            return
        }

        // Start accessing the new security-scoped resource (this will stop accessing the current one)
        guard startAccessingSecurityScopedResource(for: url) else {
            logger.error("Failed to access security-scoped resource for selected folder")
            showToast(message: "Unable to access selected folder")
            return
        }

        // Update settings and create persistent bookmark
        settings.folderPath = url
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            settings.folderBookmark = bookmark
            originalSettings.folderBookmark = bookmark
            logger.info("Created security-scoped bookmark for folder")
        } catch {
            logger.error("Failed to create bookmark for folder: \(error.localizedDescription)")
            // Don't return here - the folder selection can still work without the bookmark
        }

        if saveImmediately {
            // Save immediately and notify (used for sidebar/quick settings)
            settings.save()
            originalSettings = settings
            onSettingsSaved?(settings)
            hasUnsavedChanges = false
            showToast(message: "Folder selected: \(url.lastPathComponent)")
        } else {
            // Mark as having unsaved changes (used in settings window)
            hasUnsavedChanges = true
            showToast(message: "Folder selected: \(url.lastPathComponent)")
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

    /// Available display names for multi-monitor scaling configuration
    var availableDisplayNames: [String] {
        NSScreen.screens.enumerated().map { index, screen in
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            return name
        }
    }

    /// Get per-monitor scaling mode for a specific display
    func perMonitorScalingMode(for displayName: String) -> WallpaperScalingMode {
        settings.multiMonitorSettings.perMonitorScaling[displayName] ?? settings.scalingMode
    }

    /// Set per-monitor scaling mode for a specific display
    func setPerMonitorScalingMode(_ mode: WallpaperScalingMode, for displayName: String) {
        settings.multiMonitorSettings.perMonitorScaling[displayName] = mode
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
            hasUnsavedChanges = true
            validateSettings()
            showToast(message: "Settings imported successfully")

            logger.info("Settings imported from: \(url.path)")
            return true

        } catch {
            logger.error("Failed to import settings: \(error.localizedDescription)")
            showToast(message: "Failed to import settings")
            return false
        }
    }
}