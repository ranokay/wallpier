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

    // MARK: - Initialization

    init(wallpaperService: WallpaperServiceProtocol? = nil,
         imageScanner: ImageScannerService? = nil,
         imageCache: ImageCacheService? = nil,
         fileMonitor: FileMonitorService? = nil) {

        self.wallpaperService = wallpaperService ?? WallpaperService()
        self.imageScanner = imageScanner ?? ImageScannerService()
        self.imageCache = imageCache ?? ImageCacheService(maxCacheSizeMB: 50) // Reduced to 50MB for large images
        self.fileMonitor = fileMonitor ?? FileMonitorService()

        setupFileMonitoring()
        setupBindings()
        loadSavedState()
        loadAvailableScreens()

        logger.info("WallpaperViewModel initialized with performance optimizations")
    }

    deinit {
        // Perform synchronous cleanup only - can't call async methods in deinit
        cycleTimer?.invalidate()
        countdownTimer?.invalidate()
        fileMonitor.stopMonitoring()
        preloadingTask?.cancel()
        cancellables.removeAll()
    }

    // MARK: - Public Interface

    /// Loads initial data asynchronously
    func loadInitialData() async {
        logger.info("Loading initial data")

        guard let folderPath = settings.folderPath else {
            updateStatus("No folder selected")
            return
        }

        selectedFolderPath = folderPath
        await scanFolder(folderPath, showProgress: false)
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

    /// Stops wallpaper cycling and cleanup
    func stopCycling() {
        logger.info("Stopping wallpaper cycling")

        stopCycleTimer()
        stopPreloading()

        isRunning = false
        cycleConfiguration.isActive = false
        timeUntilNextChange = 0

        // Clear screen cycle indices to ensure fresh start next time
        screenCycleIndices.removeAll()

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

    /// Updates settings and applies changes
    func updateSettings(_ newSettings: WallpaperSettings) {
        let oldSettings = settings
        settings = newSettings

        // Apply folder change if needed
        if oldSettings.folderPath != newSettings.folderPath {
            selectedFolderPath = newSettings.folderPath

            if let folderPath = newSettings.folderPath {
                Task {
                    await scanFolder(folderPath, showProgress: true)
                }
            } else {
                // Clear current state if no folder is selected
                foundImages = []
                currentImage = nil
                updateStatus("No folder selected")
            }
        } else if newSettings.folderPath != nil {
            // Even if it's the same folder, ensure state is properly synced
            selectedFolderPath = newSettings.folderPath

            // If we don't have images but should, trigger a scan
            if foundImages.isEmpty && !isScanning {
                Task {
                    await scanFolder(newSettings.folderPath!, showProgress: false)
                }
            } else if !foundImages.isEmpty {
                // Update current image display and status
                currentImage = cycleConfiguration.currentImage
                updateStatus("Found \(foundImages.count) images")
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

    /// Scans folder with optimized progress reporting
    private func scanFolder(_ folderPath: URL, showProgress: Bool) async {
        logger.info("Starting optimized folder scan: \(folderPath.path)")

        guard !isScanning else {
            logger.warning("Scan already in progress")
            return
        }

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
                currentImage = cycleConfiguration.currentImage
                scanProgress = 0
                isScanning = false

                // Clear screen cycle indices since we have a new image list
                screenCycleIndices.removeAll()

                let message = "Found \(images.count) images in \(String(format: "%.3f", elapsed))s"
                updateStatus(message)

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

    /// Performs conservative preloading based on cycle position and memory pressure
    private func performIntelligentPreloading() async {
        // Check memory pressure first
        let memoryUsage = getCurrentMemoryUsage()
        guard memoryUsage < 500 * 1024 * 1024 else { // 500MB limit
            logger.warning("Skipping preload due to memory pressure: \(self.formatBytes(memoryUsage))")
            return
        }

        let currentIndex = cycleConfiguration.currentIndex
        var urlsToPreload: [URL] = []

        // Much more conservative preloading - only 1-2 images ahead
        let conservativeDistance = min(2, preloadDistance)

        // Preload only next image(s)
        for i in 1...conservativeDistance {
            let nextIndex = (currentIndex + i) % foundImages.count
            if nextIndex < foundImages.count {
                urlsToPreload.append(foundImages[nextIndex].url)
            }
        }

        // No previous image preloading to save memory

        guard !urlsToPreload.isEmpty else { return }

        await imageCache.preloadImages(urlsToPreload, priority: .utility)
        logger.debug("Conservatively preloaded \(urlsToPreload.count) images")
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

    /// Sets current wallpaper with performance optimization and multi-monitor support
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

    /// Goes to previous wallpaper
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

    /// Sets next wallpaper for multi-monitor setup with proper cycling
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

    /// Sets next wallpaper for independent monitor cycling
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

    /// Sets previous wallpaper for multi-monitor setup with proper cycling
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

    /// Sets previous wallpaper for independent monitor cycling
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

    /// Updates status message
    private func updateStatus(_ message: String) {
        statusMessage = message
    }

    /// Resets screen cycle indices for fresh randomization
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

    /// Cleanup resources
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