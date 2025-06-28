//
//  WallpaperViewModel.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import Combine
import OSLog
import AppKit

/// Main view model coordinating wallpaper cycling operations with performance optimizations
@MainActor
final class WallpaperViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "WallpaperViewModel")

    // MARK: - Services (Dependency Injection)

    private let wallpaperService: WallpaperServiceProtocol
    private let imageScanner: ImageScannerService
    private let imageCache: ImageCacheService
    private let fileMonitor: FileMonitorService

    // MARK: - Published State

    @Published var isRunning = false
    @Published var foundImages: [ImageFile] = []
    @Published var currentImage: ImageFile?
    @Published var currentImages: [NSScreen: ImageFile] = [:] // For multi-monitor support
    @Published var isScanning = false
    @Published var statusMessage = ""
    @Published var hasError = false
    @Published var errorMessage = ""
    @Published var selectedFolderPath: URL?
    @Published var scanProgress = 0
    @Published var timeUntilNextChange: TimeInterval = 0
    @Published var cycleProgress: Double = 0.0
    @Published var availableScreens: [(screen: NSScreen, displayName: String)] = []

    // MARK: - Settings Integration

    @Published var settings = WallpaperSettings.load() {
        didSet {
            handleSettingsChange(oldValue: oldValue)
        }
    }

    // MARK: - Performance Optimizations

    private var cancellables = Set<AnyCancellable>()
    private var cycleTimer: Timer?
    private var countdownTimer: Timer?
    private var idleCleanupTimer: Timer?
    private var cycleConfiguration = CycleConfiguration()

    // Background processing queues
    private let scanningQueue = DispatchQueue(label: "com.oxystack.wallpier.scanning", qos: .userInitiated)
    private let wallpaperQueue = DispatchQueue(label: "com.oxystack.wallpier.wallpaper", qos: .userInitiated)

    // Multi-monitor cycling state
    private var screenCycleIndices: [NSScreen: Int] = [:]

    // Performance monitoring
    private var lastWallpaperChangeTime = Date()
    private var averageChangeTime: TimeInterval = 0
    private var changeCount = 0

    /// Average time it takes to change wallpaper (for performance monitoring)
    public var averageWallpaperChangeTime: TimeInterval {
        return averageChangeTime
    }

    // Intelligent preloading
    private var preloadingTask: Task<Void, Never>?
    private let preloadDistance = 1 // Conservative: preload only next 1 image

    // UI update throttling
    private var lastUIUpdate = Date()
    private let uiUpdateInterval: TimeInterval = 0.1 // Max 10 updates per second

    // Scan throttling to prevent redundant scans
    private var lastScanTime = Date.distantPast
    private var lastScannedPath: String?
    private let scanThrottleInterval: TimeInterval = 2.0 // Min 2 seconds between scans of same folder
    private var hasCompletedInitialScan = false // Track if we've done the initial scan

    // MARK: - Initialization

    init(wallpaperService: WallpaperServiceProtocol? = nil,
         imageScanner: ImageScannerService? = nil,
         imageCache: ImageCacheService? = nil,
         fileMonitor: FileMonitorService? = nil) {

        self.wallpaperService = wallpaperService ?? WallpaperService()
        self.imageScanner = imageScanner ?? ImageScannerService()
        self.imageCache = imageCache ?? ImageCacheService(maxCacheSizeMB: 25) // Further reduced to 25MB
        self.fileMonitor = fileMonitor ?? FileMonitorService()

        setupFileMonitoring()
        setupBindings()
        loadSavedState()
        loadAvailableScreens()
        startIdleMemoryCleanup()

        logger.info("WallpaperViewModel initialized with performance optimizations")
    }

    deinit {
        // Perform synchronous cleanup only - can't call async methods in deinit
        cycleTimer?.invalidate()
        countdownTimer?.invalidate()
        idleCleanupTimer?.invalidate()
        fileMonitor.stopMonitoring()
        preloadingTask?.cancel()
        cancellables.removeAll()
    }

    // MARK: - Public Interface

            /// Loads initial data asynchronously
    func loadInitialData() async {
        logger.info("Loading initial data")

        guard let folderPath = settings.folderPath else {
            logger.info("No folder path in settings - showing folder selection prompt")
            updateStatus("No folder selected")
            return
        }

        logger.info("Found saved folder path: \(folderPath.path)")
        selectedFolderPath = folderPath

        // Only scan if we don't have images yet (avoid duplicate scans from updateSettings)
        if foundImages.isEmpty && !isScanning {
            logger.info("No images found yet, initiating folder scan")
            await scanFolder(folderPath, showProgress: false)
        } else {
            logger.info("Images already loaded (\(self.foundImages.count) images) or scan in progress, skipping scan")
        }
    }

    func startCycling() async {
        logger.info("Starting wallpaper cycling")

        guard canStartCycling else {
            updateStatus("Cannot start cycling - check folder and settings")
            return
        }

        // Ensure we have images
        if foundImages.isEmpty {
            updateStatus("Scanning images before starting...")
            guard let folderPath = selectedFolderPath else { return }
            await scanFolder(folderPath, showProgress: true)
        }

        guard !foundImages.isEmpty else {
            updateStatus("No images found in selected folder")
            return
        }

        // Configure cycle with current images
        cycleConfiguration.updateQueue(foundImages, preservePosition: false)

        if settings.isShuffleEnabled {
            cycleConfiguration.shuffleQueue()
        } else {
            cycleConfiguration.sortQueue(settings.sortOrder)
        }

        // Set initial wallpaper
        await setCurrentWallpaper()

        // Start timer and background tasks
        startCycleTimer()
        startPreloading()

        isRunning = true
        cycleConfiguration.isActive = true
        updateStatus("Cycling active")

        logger.info("Wallpaper cycling started with \(self.foundImages.count) images")
    }

    /// Stops the wallpaper cycling process, resets timers and preloading, clears per-screen cycle indices, and updates the running state and status message.
    func stopCycling() {
        logger.info("Stopping wallpaper cycling")

        stopCycleTimer()
        stopPreloading()

        isRunning = false
        cycleConfiguration.isActive = false
        timeUntilNextChange = 0

        // Clear screen cycle indices to ensure fresh start next time
        screenCycleIndices.removeAll()

        // Aggressively clean cache when stopping to reduce memory usage in standby
        Task {
            imageCache.clearCache()
            logger.info("Cleared cache on stop to reduce memory usage")
        }

        updateStatus("Cycling stopped")

        logger.info("Wallpaper cycling stopped")
    }

    /// Sets a specific wallpaper on a specific screen (for manual selection)
    func setWallpaperForScreen(_ imageFile: ImageFile, screen: NSScreen) async {
        do {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Preload the image
            let _ = await imageCache.preloadImage(from: imageFile.url)

            // Set wallpaper for the specific screen
            try await wallpaperService.setWallpaperForScreen(imageFile.url, screen: screen)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            await MainActor.run {
                // Update the specific screen's image
                currentImages[screen] = imageFile

                // Update main current image if this is the main screen
                if screen == NSScreen.main {
                    currentImage = imageFile
                }

                hasError = false
                updateChangeTimeStatistics(elapsed)

                let screenName = availableScreens.first { $0.screen == screen }?.displayName ?? "Screen"
                let message = "Set wallpaper on \(screenName): \(imageFile.name)"
                updateStatus(message)

                logger.info("\(message)")
            }

        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = error.localizedDescription
                updateStatus("Failed to set wallpaper: \(error.localizedDescription)")

                logger.error("Failed to set wallpaper for screen: \(error.localizedDescription)")
            }
        }
    }

    /// Sets a specific wallpaper on all screens
    func setWallpaperOnAllScreens(_ imageFile: ImageFile) async {
        await setWallpaper(imageFile)
    }

    /// Manually advances to next wallpaper
    func goToNextImage() {
        Task {
            await setNextWallpaper()
        }
    }

    /// Goes to previous wallpaper
    func goToPreviousImage() {
        Task {
            await setPreviousWallpaper()
        }
    }

    /// Rescans current folder
    func rescanCurrentFolder() {
        Task {
            guard let folderPath = selectedFolderPath else { return }
            await scanFolder(folderPath, showProgress: true)
        }
    }

    /// Updates the wallpaper cycling settings and applies changes such as folder selection, cycling interval, shuffle, and sort order.
    /// - Parameter newSettings: The new wallpaper settings to apply.
    ///
    /// If the folder path changes, scans the new folder or clears state if no folder is selected. If the cycling interval changes while cycling is active, restarts the timer. Shuffle or sort order changes update the cycling queue and reset per-screen cycle indices for multi-monitor setups.
    func updateSettings(_ newSettings: WallpaperSettings) {
        let oldSettings = settings
        settings = newSettings

        logger.info("Settings updated - old folder: \(oldSettings.folderPath?.path ?? "none"), new folder: \(newSettings.folderPath?.path ?? "none")")

        // Apply folder change if needed
        if oldSettings.folderPath != newSettings.folderPath {
            selectedFolderPath = newSettings.folderPath

            if let folderPath = newSettings.folderPath {
                // Always scan when folder actually changes
                Task {
                    await scanFolder(folderPath, showProgress: true)
                }
            } else {
                // Clear current state if no folder is selected
                foundImages = []
                currentImage = nil
                currentImages.removeAll()
                updateStatus("No folder selected")
            }
        } else if let folderPath = newSettings.folderPath {
            // Same folder, but ensure we're synced (important for app startup)
            selectedFolderPath = folderPath

            // Scan if we don't have images yet (e.g., on app startup)
            if foundImages.isEmpty && !isScanning {
                // Check if folder is accessible before scanning
                if FileManager.default.fileExists(atPath: folderPath.path) {
                    Task {
                        await scanFolder(folderPath, showProgress: false)
                    }
                } else {
                    logger.warning("Skipping scan - folder not accessible: \(folderPath.path)")
                    updateStatus("Selected folder is not accessible")
                }
            }
        }

        // Apply cycling interval change
        if oldSettings.cyclingInterval != newSettings.cyclingInterval && isRunning {
            restartCycleTimer()
        }

        // Apply shuffle/sort changes
        if oldSettings.isShuffleEnabled != newSettings.isShuffleEnabled ||
           oldSettings.sortOrder != newSettings.sortOrder {

            if newSettings.isShuffleEnabled {
                cycleConfiguration.shuffleQueue()
                // Reset screen indices for fresh randomization
                resetScreenCycleIndices()
            } else {
                cycleConfiguration.sortQueue(newSettings.sortOrder)
                // Reset screen indices for new order
                resetScreenCycleIndices()
            }

            // Update preview after shuffle/sort changes
            if !foundImages.isEmpty {
                currentImage = cycleConfiguration.currentImage
                setupInitialMultiMonitorPreview()
            }
        }

        // Apply multi-monitor setting changes
        if oldSettings.multiMonitorSettings.useSameWallpaperOnAllMonitors != newSettings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Update preview when multi-monitor mode changes
            if !foundImages.isEmpty {
                setupInitialMultiMonitorPreview()
            }
        }
    }

    // MARK: - Private Implementation

    /// Sets up file monitoring for automatic rescanning
    private func setupFileMonitoring() {
        fileMonitor.delegate = self
    }

    /// Sets up Combine bindings for reactive updates
    private func setupBindings() {
        // Monitor settings changes
        $settings
            .dropFirst()
            .sink { [weak self] newSettings in
                newSettings.save()
                self?.logger.debug("Settings saved automatically")
            }
            .store(in: &cancellables)
    }

    /// Loads saved state from previous session
    private func loadSavedState() {
        selectedFolderPath = settings.folderPath

        // Load cache statistics for monitoring
        Task {
            let stats = imageCache.getCacheStatistics()
            logger.debug("Cache loaded with \(stats.formattedSize)")
        }
    }

    /// Loads available screens for multi-monitor support
    private func loadAvailableScreens() {
        if let wallpaperService = wallpaperService as? WallpaperService {
            self.availableScreens = wallpaperService.getScreensInfo()
            logger.info("Loaded \(self.availableScreens.count) available screen(s)")
        }
    }

    /// Handles settings changes with intelligent updates
    private func handleSettingsChange(oldValue: WallpaperSettings) {
        // Update cache configuration if needed
        if oldValue.advancedSettings.maxCacheSizeMB != settings.advancedSettings.maxCacheSizeMB {
            Task {
                await imageCache.optimizeCache()
            }
        }

        // Update file monitoring if folder changed
        if oldValue.folderPath != settings.folderPath {
            if let folderPath = settings.folderPath {
                startFolderMonitoring(folderPath)
            } else {
                stopFolderMonitoring()
            }
        }
    }

    /// Asynchronously scans the specified folder for images, updating progress and handling errors.
    /// - Parameters:
    ///   - folderPath: The URL of the folder to scan.
    ///   - showProgress: Indicates whether to display scan progress.
    ///
    /// Uses an optimized scanning strategy based on folder size and settings, updates the list of found images, resets per-screen cycle indices, and initiates image preloading if images are found. Updates scanning state and error messages as appropriate.
        private func scanFolder(_ folderPath: URL, showProgress: Bool) async {
        // Throttle redundant scans of the same folder, BUT allow initial scan on app startup
        let currentPath = folderPath.path
        let timeSinceLastScan = Date().timeIntervalSince(lastScanTime)

        if hasCompletedInitialScan && currentPath == lastScannedPath && timeSinceLastScan < scanThrottleInterval {
            logger.debug("Skipping redundant scan of \(currentPath) (scanned \(String(format: "%.1f", timeSinceLastScan))s ago)")
            return
        }

        logger.info("Starting optimized folder scan: \(folderPath.path)")

        guard !isScanning else {
            logger.warning("Scan already in progress")
            return
        }

        lastScanTime = Date()
        lastScannedPath = currentPath

        isScanning = true
        scanProgress = 0
        hasError = false
        updateStatus("Scanning images...")

        do {
            let images: [ImageFile] = try await PerformanceMonitor.shared.timeAsync("folder_scan") {
                // Use quick scan for faster results if folder is large
                let useQuickScan = shouldUseQuickScan(for: folderPath)

                if useQuickScan {
                    return try await imageScanner.quickScanDirectory(folderPath, maxDepth: 3)
                } else if settings.isRecursiveScanEnabled {
                    return try await imageScanner.scanDirectoryRecursively(folderPath) { [weak self] progress in
                        Task { @MainActor in
                            if showProgress {
                                self?.throttledUIUpdate {
                                    self?.scanProgress = progress
                                }
                            }
                        }
                    }
                } else {
                    return try await imageScanner.scanDirectory(folderPath)
                }
            }

            // Record scan performance
            let elapsed = PerformanceMonitor.shared.averageScanTime
            PerformanceMonitor.shared.recordScanTime(elapsed, imageCount: images.count)

            await MainActor.run {
                foundImages = images
                scanProgress = 0
                isScanning = false

                // Clear screen cycle indices since we have a new image list
                screenCycleIndices.removeAll()

                // Set up cycle configuration with new images
                if !images.isEmpty {
                    cycleConfiguration.updateQueue(images, preservePosition: false)

                    // Apply shuffle or sort based on current settings
                    if settings.isShuffleEnabled {
                        cycleConfiguration.shuffleQueue()
                    } else {
                        cycleConfiguration.sortQueue(settings.sortOrder)
                    }

                    // Set the first image as current for preview
                    currentImage = cycleConfiguration.currentImage

                    // Set up multi-monitor preview if needed
                    setupInitialMultiMonitorPreview()
                } else {
                    currentImage = nil
                    currentImages.removeAll()
                }

                let message = "Found \(images.count) images in \(String(format: "%.3f", elapsed))s"
                updateStatus(message)

                // Mark that we've completed at least one scan (for throttling logic)
                hasCompletedInitialScan = true

                logger.info("Scan completed: \(message)")
            }

            // Start intelligent preloading
            if !images.isEmpty {
                await startIntelligentPreloading()
            }

        } catch {
            await MainActor.run {
                isScanning = false
                hasError = true
                errorMessage = error.localizedDescription
                updateStatus("Scan failed: \(error.localizedDescription)")

                logger.error("Folder scan failed: \(error.localizedDescription)")
            }
        }
    }

    /// Determines if quick scan should be used based on folder characteristics
    private func shouldUseQuickScan(for folderPath: URL) -> Bool {
        // Use quick scan for network volumes or if folder seems large
        let path = folderPath.path
        return path.contains("/Volumes/") ||
               path.contains("/Network/") ||
               ((try? FileManager.default.contentsOfDirectory(atPath: path).count) ?? 0) > 1000
    }

    /// Starts intelligent preloading of upcoming images
    private func startIntelligentPreloading() async {
        guard settings.advancedSettings.preloadNextImage else {
            preloadingTask?.cancel()
            preloadingTask = nil
            return
        }
        guard !foundImages.isEmpty else { return }

        preloadingTask?.cancel()
        preloadingTask = Task(priority: .utility) { [weak self] in
            await self?.performIntelligentPreloading()
        }
    }

    /// Performs ultra-conservative preloading based on cycle position and memory pressure
    private func performIntelligentPreloading() async {
        // Check memory pressure first with stricter limit
        let memoryUsage = getCurrentMemoryUsage()
        guard memoryUsage < 150 * 1024 * 1024 else { // Much stricter 150MB limit
            logger.warning("Skipping preload due to memory pressure: \(self.formatBytes(memoryUsage))")
            return
        }

        // Only preload if actively cycling
        guard isRunning else {
            logger.debug("Skipping preload - not actively cycling")
            return
        }

        let currentIndex = cycleConfiguration.currentIndex
        var urlsToPreload: [URL] = []

        // Ultra-conservative preloading - only next image when actively cycling
        let nextIndex = (currentIndex + 1) % foundImages.count
        if nextIndex < foundImages.count {
            urlsToPreload.append(foundImages[nextIndex].url)
        }

        guard !urlsToPreload.isEmpty else { return }

        await imageCache.preloadImages(urlsToPreload, priority: .utility)
        logger.debug("Ultra-conservatively preloaded \(urlsToPreload.count) image")
    }

    /// Gets current app memory usage
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    /// Format bytes for logging
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Sets the current wallpaper(s) based on the multi-monitor configuration.
    /// - If using the same wallpaper on all monitors, sets the current image on every screen.
    /// - If using independent wallpapers per monitor, assigns each screen a starting image, initializing per-screen indices for cycling.
    private func setCurrentWallpaper() async {
        guard !foundImages.isEmpty else {
            updateStatus("No images available")
            return
        }

        if settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Use single wallpaper for all monitors
            guard let imageFile = cycleConfiguration.currentImage else {
                updateStatus("No current image available")
                return
            }
            await setWallpaper(imageFile)
        } else {
            // Set different wallpapers for each monitor from the start
            let screens = NSScreen.screens
            var imageURLs: [URL] = []
            var initialImages: [NSScreen: ImageFile] = [:]

            // Initialize screen cycle indices with proper starting points
            screenCycleIndices.removeAll()

            for (screenIndex, screen) in screens.enumerated() {
                let startIndex: Int
                if settings.isShuffleEnabled {
                    // Random starting point for each screen
                    startIndex = Int.random(in: 0..<foundImages.count)
                } else {
                    // Staggered starting points for each screen
                    startIndex = screenIndex % foundImages.count
                }

                screenCycleIndices[screen] = startIndex
                let imageFile = foundImages[startIndex]
                initialImages[screen] = imageFile
                imageURLs.append(imageFile.url)
            }

            await setMultipleWallpapers(imageURLs, newImages: initialImages)
        }
    }

    /// Advances to next wallpaper
    private func setNextWallpaper() async {
        if settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Standard single-image cycling
            guard let nextImage = cycleConfiguration.advanceToNext() else {
                updateStatus("No next image available")
                return
            }
            await setWallpaper(nextImage)
        } else {
            // Multi-monitor cycling with different images per screen
            await setNextWallpaperMultiMonitor()
        }

        updateCycleProgress()

        // Update preloading based on new position
        await startIntelligentPreloading()
    }

    /// Advances to the previous wallpaper in the cycle, applying it to all screens or individually per monitor based on multi-monitor settings.
    ///
    /// In single-wallpaper mode, sets the previous image on all monitors. In multi-monitor mode, cycles each screen to its own previous image.
    /// Updates cycle progress after changing wallpapers.
    private func setPreviousWallpaper() async {
        if settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Standard single-image cycling
            guard let prevImage = cycleConfiguration.goToPrevious() else {
                updateStatus("No previous image available")
                return
            }
            await setWallpaper(prevImage)
        } else {
            // Multi-monitor cycling with different images per screen
            await setPreviousWallpaperMultiMonitor()
        }

        updateCycleProgress()
    }

    /// Advances to the next wallpaper for each monitor, applying either the same or different images per screen based on multi-monitor settings.
    /// - Note: If using the same wallpaper on all monitors, advances globally; otherwise, each monitor cycles independently. Updates the displayed wallpapers accordingly.
    private func setNextWallpaperMultiMonitor() async {
        guard !foundImages.isEmpty else {
            updateStatus("No images available")
            return
        }

        let screens = NSScreen.screens
        var imageURLs: [URL] = []
        var nextImages: [NSScreen: ImageFile] = [:]

        if settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Use same wallpaper on all monitors - advance from current image
            guard let nextImage = cycleConfiguration.advanceToNext() else {
                updateStatus("No next image available")
                return
            }

            for screen in screens {
                nextImages[screen] = nextImage
                imageURLs.append(nextImage.url)
            }
        } else {
            // Use different wallpapers on each monitor with proper individual cycling
            await setNextWallpaperIndependentMonitors(&nextImages, &imageURLs)
        }

        await setMultipleWallpapers(imageURLs, newImages: nextImages)
    }

    /// Advances the wallpaper for each monitor independently by updating their respective cycling indices.
    /// - Parameters:
    ///   - nextImages: A dictionary to be updated with the next image for each screen.
    ///   - imageURLs: An array to be appended with the URLs of the next images for all screens.
    ///
    /// Initializes per-screen cycling indices if not already set, then advances each screen to its next image based on its own index. Shuffle or staggered starting points are used depending on settings.
    private func setNextWallpaperIndependentMonitors(_ nextImages: inout [NSScreen: ImageFile], _ imageURLs: inout [URL]) async {
        let screens = NSScreen.screens

        // Create or maintain separate cycling indices for each screen
        if screenCycleIndices.isEmpty {
            // Initialize indices for each screen with different starting points
            for (index, screen) in screens.enumerated() {
                let startIndex: Int
                if settings.isShuffleEnabled {
                    // Random starting point for each screen
                    startIndex = Int.random(in: 0..<foundImages.count)
                } else {
                    // Staggered starting points for each screen
                    startIndex = index % foundImages.count
                }
                screenCycleIndices[screen] = startIndex
            }
        }

        // Advance each screen's index independently
        for screen in screens {
            var currentScreenIndex = screenCycleIndices[screen] ?? 0

            // Advance to next image for this specific screen
            currentScreenIndex = (currentScreenIndex + 1) % foundImages.count
            screenCycleIndices[screen] = currentScreenIndex

            let nextImage = foundImages[currentScreenIndex]
            nextImages[screen] = nextImage
            imageURLs.append(nextImage.url)
        }
    }

    /// Sets the previous wallpaper on each monitor, using either the same image for all screens or cycling each screen independently based on multi-monitor settings.
    private func setPreviousWallpaperMultiMonitor() async {
        guard !foundImages.isEmpty else {
            updateStatus("No images available")
            return
        }

        let screens = NSScreen.screens
        var imageURLs: [URL] = []
        var prevImages: [NSScreen: ImageFile] = [:]

        if settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Use same wallpaper on all monitors - go back from current image
            guard let prevImage = cycleConfiguration.goToPrevious() else {
                updateStatus("No previous image available")
                return
            }

            for screen in screens {
                prevImages[screen] = prevImage
                imageURLs.append(prevImage.url)
            }
        } else {
            // Use different wallpapers on each monitor with proper individual cycling
            await setPreviousWallpaperIndependentMonitors(&prevImages, &imageURLs)
        }

        await setMultipleWallpapers(imageURLs, newImages: prevImages)
    }

    /// Advances each monitor to its previous wallpaper in the cycle, updating per-screen indices independently.
    /// - Parameters:
    ///   - prevImages: A dictionary to be updated with the previous image for each screen.
    ///   - imageURLs: An array to be updated with the URLs of the previous images for all screens.
    private func setPreviousWallpaperIndependentMonitors(_ prevImages: inout [NSScreen: ImageFile], _ imageURLs: inout [URL]) async {
        let screens = NSScreen.screens

        // Ensure indices are initialized
        if screenCycleIndices.isEmpty {
            // Initialize indices for each screen with different starting points
            for (index, screen) in screens.enumerated() {
                let startIndex: Int
                if settings.isShuffleEnabled {
                    // Random starting point for each screen
                    startIndex = Int.random(in: 0..<foundImages.count)
                } else {
                    // Staggered starting points for each screen
                    startIndex = index % foundImages.count
                }
                screenCycleIndices[screen] = startIndex
            }
        }

        // Go back on each screen's index independently
        for screen in screens {
            var currentScreenIndex = screenCycleIndices[screen] ?? 0

            // Go back to previous image for this specific screen
            currentScreenIndex = currentScreenIndex == 0 ? foundImages.count - 1 : currentScreenIndex - 1
            screenCycleIndices[screen] = currentScreenIndex

            let prevImage = foundImages[currentScreenIndex]
            prevImages[screen] = prevImage
            imageURLs.append(prevImage.url)
        }
    }

        /// Sets multiple wallpapers for multi-monitor setup
    private func setMultipleWallpapers(_ imageURLs: [URL], newImages: [NSScreen: ImageFile]) async {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // Skip aggressive preloading to prevent memory explosion
            // Images will be loaded on-demand by the wallpaper service
            logger.debug("Setting multiple wallpapers for monitors: \(imageURLs.count) images")

            try await wallpaperService.setWallpaperForMultipleMonitors(imageURLs, multiMonitorSettings: settings.multiMonitorSettings)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            await MainActor.run {
                // Update currentImages AFTER successful wallpaper setting to ensure sync
                currentImages = newImages

                // Update current image to the first screen's image for compatibility
                if let firstScreen = NSScreen.screens.first,
                   let firstImage = newImages[firstScreen] {
                    currentImage = firstImage
                }

                hasError = false
                updateChangeTimeStatistics(elapsed)

                let message = "Set wallpapers for \(imageURLs.count) screen(s) (\(String(format: "%.3f", elapsed))s)"
                updateStatus(message)

                logger.info("\(message)")
            }

        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = error.localizedDescription
                updateStatus("Failed to set wallpapers: \(error.localizedDescription)")

                logger.error("Failed to set multi-monitor wallpapers: \(error.localizedDescription)")
            }
        }
    }

    /// Sets wallpaper with caching and error handling
    private func setWallpaper(_ imageFile: ImageFile) async {
        do {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Try to get from cache first for faster transitions
            let _ = await imageCache.preloadImage(from: imageFile.url)

            // Set wallpaper with multi-monitor support
            try await wallpaperService.setWallpaper(imageFile.url, multiMonitorSettings: settings.multiMonitorSettings)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            await MainActor.run {
                currentImage = imageFile

                // Update all screens with same image if using same wallpaper mode
                if settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
                    for screen in NSScreen.screens {
                        currentImages[screen] = imageFile
                    }
                } else {
                    // Only update the main screen
                    if let mainScreen = NSScreen.main {
                        currentImages[mainScreen] = imageFile
                    }
                }

                hasError = false

                updateChangeTimeStatistics(elapsed)

                let message = "Set wallpaper: \(imageFile.name) (\(String(format: "%.3f", elapsed))s)"
                updateStatus(message)

                logger.info("\(message)")
            }

        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = error.localizedDescription
                updateStatus("Failed to set wallpaper: \(error.localizedDescription)")

                logger.error("Failed to set wallpaper: \(error.localizedDescription)")
            }
        }
    }

    /// Updates wallpaper change performance statistics
    private func updateChangeTimeStatistics(_ elapsed: TimeInterval) {
        changeCount += 1
        averageChangeTime = (averageChangeTime * Double(changeCount - 1) + elapsed) / Double(changeCount)
        lastWallpaperChangeTime = Date()

        // Log performance metrics periodically
        if changeCount % 10 == 0 {
            logger.info("Average wallpaper change time: \(String(format: "%.3f", self.averageChangeTime))s over \(self.changeCount) changes")
        }
    }

    /// Starts cycling timer with performance optimization
    private func startCycleTimer() {
        stopCycleTimer()

        // Validate cycling interval to prevent timer creation issues
        let interval = settings.cyclingInterval
        guard interval.isFinite && interval > 0 && interval <= 86400 else {
            logger.error("Invalid cycling interval: \(interval). Using default of 300 seconds.")
            settings.cyclingInterval = 300 // Reset to 5 minutes default
            return startCycleTimer() // Retry with valid interval
        }

        cycleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.setNextWallpaper()
            }
        }

        timeUntilNextChange = interval
        startCountdownTimer()

        logger.debug("Cycle timer started with interval: \(interval)s")
    }

    /// Starts countdown timer for UI updates
    private func startCountdownTimer() {
        stopCountdownTimer()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
    }

    /// Updates countdown display
    private func updateCountdown() {
        guard isRunning else { return }

        timeUntilNextChange = max(0, timeUntilNextChange - 1)

        if timeUntilNextChange <= 0 {
            timeUntilNextChange = settings.cyclingInterval
        }
    }

    /// Stops cycling timer
    private func stopCycleTimer() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        stopCountdownTimer()
    }

    /// Stops countdown timer
    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    /// Restarts cycle timer with new interval
    private func restartCycleTimer() {
        if isRunning {
            startCycleTimer()
        }
    }

    /// Starts idle memory cleanup timer to reduce memory usage when not cycling
    private func startIdleMemoryCleanup() {
        idleCleanupTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Only clean up when not actively cycling
            Task { @MainActor in
                if !self.isRunning {
                    await self.imageCache.optimizeCache()
                    self.logger.debug("Performed idle memory cleanup")
                }
            }
        }

        logger.debug("Started idle memory cleanup timer (3 minutes interval)")
    }

    /// Starts preloading task
    private func startPreloading() {
        Task {
            await startIntelligentPreloading()
        }
    }

    /// Stops preloading task
    private func stopPreloading() {
        preloadingTask?.cancel()
        preloadingTask = nil
    }

    /// Updates cycle progress indicator
    private func updateCycleProgress() {
        cycleProgress = cycleConfiguration.cycleProgress
    }

    /// Starts monitoring folder for changes
    private func startFolderMonitoring(_ folderPath: URL) {
        do {
            try fileMonitor.startMonitoring(folderPath) { [weak self] in
                Task { @MainActor in
                    self?.logger.info("Folder changes detected, rescanning...")
                    await self?.scanFolder(folderPath, showProgress: false)
                }
            }
            logger.info("Started monitoring folder: \(folderPath.path)")
        } catch {
            logger.error("Failed to start folder monitoring: \(error.localizedDescription)")
        }
    }

    /// Stops monitoring folder
    private func stopFolderMonitoring() {
        fileMonitor.stopMonitoring()
        logger.info("Stopped folder monitoring")
    }

    /// Throttled UI update to prevent excessive refreshes
    private func throttledUIUpdate(_ update: @escaping () -> Void) {
        let now = Date()
        if now.timeIntervalSince(lastUIUpdate) >= uiUpdateInterval {
            lastUIUpdate = now
            update()
        }
    }

    /// Updates the current status message displayed by the view model.
    /// - Parameter message: The new status message to set.
    private func updateStatus(_ message: String) {
        statusMessage = message
    }

    /// Sets up initial multi-monitor preview without actually setting wallpapers
    private func setupInitialMultiMonitorPreview() {
        guard !foundImages.isEmpty else { return }

        let screens = NSScreen.screens

        if settings.multiMonitorSettings.useSameWallpaperOnAllMonitors {
            // Use the same first image for all screens in preview
            if let firstImage = cycleConfiguration.currentImage {
                for screen in screens {
                    currentImages[screen] = firstImage
                }
            }
        } else {
            // Set up different images for each screen for preview
            var initialImages: [NSScreen: ImageFile] = [:]

            // Initialize screen cycle indices
            screenCycleIndices.removeAll()

            for (screenIndex, screen) in screens.enumerated() {
                let startIndex: Int
                if settings.isShuffleEnabled {
                    // Random starting point for each screen
                    startIndex = Int.random(in: 0..<foundImages.count)
                } else {
                    // Staggered starting points for each screen
                    startIndex = screenIndex % foundImages.count
                }

                screenCycleIndices[screen] = startIndex
                initialImages[screen] = foundImages[startIndex]
            }

            currentImages = initialImages
        }

        logger.debug("Set up initial multi-monitor preview for \(screens.count) screens")
    }

    /// Resets the wallpaper cycling indices for each screen based on the current shuffle setting.
    /// - Note: In shuffle mode, each screen starts at a random image; otherwise, starting indices are staggered across screens.
    private func resetScreenCycleIndices() {
        guard !foundImages.isEmpty else { return }

        let screens = NSScreen.screens
        screenCycleIndices.removeAll()

        for (index, screen) in screens.enumerated() {
            let startIndex: Int
            if settings.isShuffleEnabled {
                // Random starting point for each screen
                startIndex = Int.random(in: 0..<foundImages.count)
            } else {
                // Staggered starting points for each screen
                startIndex = index % foundImages.count
            }
            screenCycleIndices[screen] = startIndex
        }

        logger.debug("Reset screen cycle indices for \(screens.count) screens")
    }

    /// Cleans up resources and stops all ongoing operations managed by the view model.
    private func cleanup() {
        stopCycling()
        stopFolderMonitoring()
        preloadingTask?.cancel()
        cancellables.removeAll()

        logger.info("WallpaperViewModel cleaned up")
    }
}

// MARK: - Computed Properties

extension WallpaperViewModel {
    var canStartCycling: Bool {
        return !isScanning &&
               selectedFolderPath != nil &&
               settings.cyclingInterval > 0 &&
               !isRunning
    }

    var canAdvance: Bool {
        return !foundImages.isEmpty && cycleConfiguration.canAdvance
    }

    var canGoBack: Bool {
        return !foundImages.isEmpty && cycleConfiguration.canGoBack
    }

    var cyclingInterval: TimeInterval {
        get { settings.cyclingInterval }
        set {
            settings.cyclingInterval = newValue
            if isRunning {
                restartCycleTimer()
            }
        }
    }

    var isShuffleEnabled: Bool {
        get { settings.isShuffleEnabled }
        set {
            settings.isShuffleEnabled = newValue
            if newValue {
                cycleConfiguration.shuffleQueue()
            } else {
                cycleConfiguration.sortQueue(settings.sortOrder)
            }
            updateCycleProgress()
        }
    }
}

// MARK: - FileMonitorDelegate

extension WallpaperViewModel: FileMonitorDelegate {
    func fileMonitorDidDetectChanges(_ monitor: FileMonitorService, in directory: URL) async {
        logger.info("File system changes detected in \(directory.path)")

        // Debounce rapid changes
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        if !isScanning {
            await scanFolder(directory, showProgress: false)
        }
    }

    func fileMonitorDidFailWithError(_ monitor: FileMonitorService, error: Error) async {
        logger.error("File monitoring error: \(error.localizedDescription)")

        await MainActor.run {
            hasError = true
            errorMessage = "File monitoring failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Performance Monitoring

extension WallpaperViewModel {
    /// Gets performance statistics for monitoring
    func getPerformanceStatistics() -> [String: Any] {
        let cacheStats = imageCache.getCacheStatistics()
        return [
            "isRunning": isRunning,
            "imagesFound": foundImages.count,
            "averageChangeTime": averageChangeTime,
            "totalChanges": changeCount,
            "cacheHitRate": cacheStats.hitRate,
            "isScanning": isScanning,
            "cycleProgress": cycleProgress
        ]
    }

    /// Logs performance statistics
    func logPerformanceStatistics() {
        let stats = getPerformanceStatistics()
        logger.info("Performance stats: \(stats)")
    }
}