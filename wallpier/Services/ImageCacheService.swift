//
//  ImageCacheService.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import AppKit
import ImageIO
import OSLog
import Combine

// Note: ImageCacheServiceProtocol is defined in Utilities/Protocols.swift

/// Service responsible for efficient image caching with performance optimizations
@MainActor
@preconcurrency final class ImageCacheService: ImageCacheServiceProtocol {
    private let logger = Logger.cache

    /// Multi-level caching system
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let metadataCache = NSCache<NSString, ImageMetadata>()

    /// Disk-based thumbnail cache for persistence
    private let thumbnailCacheManager = ThumbnailCacheManager()

    /// Keep track of keys in the cache for eviction strategy
    private var cachedImageKeys = Set<NSString>()

    /// Concurrent queues for different priorities
    private let highPriorityQueue = DispatchQueue(label: "com.oxystack.wallpier.imagecache.high", qos: .userInitiated, attributes: .concurrent)
    private let backgroundQueue = DispatchQueue(label: "com.oxystack.wallpier.imagecache.background", qos: .utility, attributes: .concurrent)

    /// Performance optimization settings
    private var maxCacheSize: Int
    private var enableLogging: Bool
    private let maxThumbnailSize: Int = 10 * 1024 * 1024 // 10MB for thumbnails
    private let preloadBatchSize = 2 // Very conservative batch size
    private let maxConcurrentLoads = 4

    /// Memory pressure monitoring
    private var isUnderMemoryPressure = false
    private var lastMemoryWarning = Date.distantPast
    private let memoryWarningCooldown: TimeInterval = 30.0

    /// Cache statistics for monitoring
    private var cacheHits = 0
    private var cacheMisses = 0
    private var preloadRequests = 0

    /// Timers for maintenance/logging
    private var optimizeTimer: Timer?
    private var logTimer: Timer?

    /// Enhanced metadata for intelligent caching
    class ImageMetadata: NSObject {
        let fileSize: Int
        var lastAccessed: Date
        let imageSize: CGSize
        var accessCount: Int
        let cacheTime: Date
        var priority: Int // Higher = more important
        private var consecutiveHits: Int = 0

        init(fileSize: Int, lastAccessed: Date, imageSize: CGSize, priority: Int = 1) {
            self.fileSize = fileSize
            self.lastAccessed = lastAccessed
            self.imageSize = imageSize
            self.accessCount = 1
            self.cacheTime = Date()
            self.priority = priority
        }

        func updateAccess() {
            lastAccessed = Date()
            accessCount += 1
            consecutiveHits += 1
        }

        /// Improved scoring algorithm with better differentiation
        var retentionScore: Double {
            let now = Date()
            let timeSinceCache = now.timeIntervalSince(cacheTime)
            let timeSinceAccess = now.timeIntervalSince(lastAccessed)

            // Age penalty (images get less valuable over time)
            let agePenalty = min(timeSinceCache / 3600.0, 10.0) // Hours since cached

            // Access frequency bonus (heavily weight recent and frequent access)
            let accessFrequency = Double(accessCount) / max(timeSinceCache / 60.0, 1.0) // accesses per minute
            let accessBonus = min(accessFrequency * 5.0, 10.0)

            // Recency bonus (recently accessed items are more valuable)
            let recencyBonus = max(0, 10.0 - timeSinceAccess / 60.0) // Minutes since last access

            // Size penalty (larger images are more expensive to keep)
            let sizePenalty = log10(Double(fileSize) / (1024 * 1024)) // MB in log scale

            // Priority bonus
            let priorityBonus = Double(priority) * 2.0

            // Consecutive hits bonus (hot images)
            let hotBonus = min(Double(consecutiveHits) * 0.5, 3.0)

            let score = accessBonus + recencyBonus + priorityBonus + hotBonus - agePenalty - sizePenalty
            return max(0.1, score) // Ensure minimum score
        }
    }

    init(maxCacheSizeMB: Int = 25, enableLogging: Bool = false) {
        self.maxCacheSize = max(5, min(maxCacheSizeMB, 100)) // Much more conservative range
        self.enableLogging = enableLogging
        configureCache()
        setupMemoryManagement()

        logger.info("ImageCacheService initialized with \(self.maxCacheSize)MB limit (logging: \(enableLogging))")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        optimizeTimer?.invalidate()
        logTimer?.invalidate()
    }

    /// Configures all cache layers with aggressive memory limits
    private func configureCache() {
        let totalCostLimit = maxCacheSize * 1024 * 1024

        // Reduce cache sizes significantly for large images
        imageCache.totalCostLimit = Int(Double(totalCostLimit) * 0.6) // Reduced from 70%
        imageCache.countLimit = min(20, maxCacheSize / 4) // Much more aggressive limit
        imageCache.evictsObjectsWithDiscardedContent = true

        // Thumbnail cache - higher count limit since thumbnails are small (~50KB each)
        // 300 thumbnails * 50KB = ~15MB which is acceptable for gallery browsing
        thumbnailCache.totalCostLimit = Int(Double(totalCostLimit) * 0.3) // Increased from 20%
        thumbnailCache.countLimit = 300 // Increased from 50 to support larger galleries
        thumbnailCache.evictsObjectsWithDiscardedContent = true

        // Metadata cache
        metadataCache.totalCostLimit = Int(Double(totalCostLimit) * 0.1)
        metadataCache.countLimit = 100
        metadataCache.evictsObjectsWithDiscardedContent = true

        logger.info("Cache configured: Main=\(self.imageCache.totalCostLimit/1024/1024)MB, Thumbnails=\(self.thumbnailCache.totalCostLimit/1024/1024)MB")
    }

    /// Sets up memory pressure monitoring and automatic cleanup
    private func setupMemoryManagement() {
        // Only perform background cleanup when app goes inactive (not optimization on every activation)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.performBackgroundCleanup() }
        }

        // Periodic optimization (less frequent) and optional statistics reporting
        optimizeTimer?.invalidate()
        optimizeTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { await self?.optimizeCache() }
        }

        logTimer?.invalidate()
        if enableLogging {
            logTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.logCacheStatistics()
                }
            }
        }
    }

    /// Updates cache sizing and logging configuration at runtime
    func updateConfiguration(maxCacheSizeMB: Int, enableLogging: Bool) {
        let clampedSize = max(5, min(maxCacheSizeMB, 100))
        let shouldReconfigure = clampedSize != maxCacheSize || enableLogging != self.enableLogging

        guard shouldReconfigure else { return }

        logger.info("Updating cache configuration: size \(clampedSize)MB, logging: \(enableLogging)")
        maxCacheSize = clampedSize
        self.enableLogging = enableLogging
        configureCache()
        setupMemoryManagement()
    }

    /// Caches an image with enhanced metadata and smart eviction
    func cacheImage(_ image: NSImage, for url: URL) {
        let key = url.absoluteString as NSString

        // Prevent duplicate caching
        if cachedImageKeys.contains(key) {
            updateAccessMetadata(for: key) // Just update access
            return
        }

        let cost = estimateImageMemorySize(image)

        // Much stricter size limits
        guard cost > 0 && cost < 20 * 1024 * 1024 else { // Max 20MB per image
            logger.warning("Rejecting oversized image: \(url.lastPathComponent) (\(self.formatBytes(cost)))")
            return
        }

        // Check memory pressure before caching with much stricter limit
        let currentMemory = getCurrentMemoryUsage()
        if currentMemory > 150 * 1024 * 1024 { // Much stricter 150MB limit
            logger.warning("Rejecting cache due to memory pressure: \(self.formatBytes(currentMemory))")
            Task { await performAggressiveCleanup() }
            return
        }

        let priority = determineCachePriority(url: url, imageSize: image.size)

        // Smart cache placement based on size and usage
        if cost < 2 * 1024 * 1024 { // Small images (< 2MB)
            imageCache.setObject(image, forKey: key, cost: cost)
            logger.debug("Cached to main: \(url.lastPathComponent) (\(self.formatBytes(cost)), priority: \(priority))")
        } else {
            // Large images: store optimized thumbnail only
            if let thumbnail = createThumbnail(from: image, maxSize: 256) {
                let thumbnailCost = estimateImageMemorySize(thumbnail)
                thumbnailCache.setObject(thumbnail, forKey: key, cost: thumbnailCost)
                logger.debug("Cached thumbnail: \(url.lastPathComponent) (\(self.formatBytes(thumbnailCost)), priority: \(priority))")
            }
        }

        // Store metadata
        let metadata = ImageMetadata(
            fileSize: cost,
            lastAccessed: Date(),
            imageSize: image.size,
            priority: priority
        )
        metadataCache.setObject(metadata, forKey: key)
        cachedImageKeys.insert(key)

        // Proactive cleanup if nearing limits
        if shouldPerformCleanup() {
            Task { await performSmartEviction() }
        }
    }

    /// Retrieves cached image with hit rate tracking
    func getCachedImage(for url: URL) -> NSImage? {
        let key = url.absoluteString as NSString

        // Try main cache first
        if let image = imageCache.object(forKey: key) {
            updateAccessMetadata(for: key)
            cacheHits += 1
            logger.debug("Main cache hit: \(url.lastPathComponent)")
            return image
        }

        // Try thumbnail cache
        if let thumbnail = thumbnailCache.object(forKey: key) {
            updateAccessMetadata(for: key)
            cacheHits += 1
            logger.debug("Thumbnail cache hit: \(url.lastPathComponent)")
            return thumbnail
        }

        cacheMisses += 1
        logger.debug("Cache miss: \(url.lastPathComponent)")
        return nil
    }

    /// High-performance image preloading
    func preloadImage(from url: URL) async -> NSImage? {
        // Check cache first
        if let cachedImage = getCachedImage(for: url) {
            return cachedImage
        }

        preloadRequests += 1

        return await withCheckedContinuation { continuation in
            backgroundQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                // Load image with size optimization on main actor
                Task {
                    let image = await MainActor.run {
                        return self.loadImageOptimized(from: url)
                    }

                    guard let image = image else {
                        await MainActor.run {
                            self.logger.debug("Failed to preload: \(url.lastPathComponent)")
                        }
                        continuation.resume(returning: nil)
                        return
                    }

                    // Cache the image on main actor
                    await MainActor.run {
                        self.cacheImage(image, for: url)
                    }
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// Batch preloading with strict memory pressure and concurrency control
    func preloadImages(_ urls: [URL], priority: TaskPriority = .medium) async {
        // Check memory pressure before starting batch preload with much stricter limit
        let currentMemory = getCurrentMemoryUsage()
        if currentMemory > 150 * 1024 * 1024 { // Much stricter 150MB limit for batch operations
            logger.warning("Skipping batch preload due to memory pressure: \(self.formatBytes(currentMemory))")
            return
        }

        // Much more limited batch size - maximum 1 image at a time
        let limitedUrls = Array(urls.prefix(1))

        logger.info("Starting ultra-conservative batch preload of \(limitedUrls.count) images (from \(urls.count) requested)")

        let startTime = CFAbsoluteTimeGetCurrent()

        // Process images sequentially to prevent memory spikes
        for url in limitedUrls {
            // Check memory before each image with stricter limit
            let memoryCheck = getCurrentMemoryUsage()
            if memoryCheck > 200 * 1024 * 1024 { // Much stricter 200MB absolute limit
                logger.warning("Aborting preload due to memory limit: \(self.formatBytes(memoryCheck))")
                break
            }

            await preloadBatch([url])
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Batch preload completed in \(String(format: "%.3f", elapsed))s")
    }

    /// Clears entire cache with selective preservation
    func clearCache() {
        let stats = getCacheStatistics()

        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        metadataCache.removeAllObjects()
        cachedImageKeys.removeAll() // Clear all keys

        // Reset statistics
        cacheHits = 0
        cacheMisses = 0
        preloadRequests = 0

        logger.info("Cache cleared (was: \(stats.formattedSize))")
    }

    /// Removes specific cached image
    func removeCachedImage(for url: URL) {
        let key = url.absoluteString as NSString

        imageCache.removeObject(forKey: key)
        thumbnailCache.removeObject(forKey: key)
        metadataCache.removeObject(forKey: key)
        cachedImageKeys.remove(key) // Remove key from our tracking set

        logger.debug("Removed cached image: \(url.lastPathComponent)")
    }

    /// Gets current cache size with accurate calculation
    func getCacheSize() -> Int {
        // This is an approximation since NSCache doesn't expose exact size
        let estimatedMainCache = min(imageCache.totalCostLimit, maxCacheSize * 1024 * 1024 * 7 / 10)
        let estimatedThumbnailCache = min(thumbnailCache.totalCostLimit, maxCacheSize * 1024 * 1024 * 2 / 10)
        return estimatedMainCache + estimatedThumbnailCache
    }

    // MARK: - Thumbnail Caching for Gallery

    /// Cache a thumbnail for the gallery view (persists across gallery opens)
    func cacheThumbnail(_ image: NSImage, for url: URL, size: CGFloat) {
        let key = thumbnailKey(for: url, size: size)
        let cost = estimateImageMemorySize(image)

        // Don't cache if under memory pressure
        guard !isUnderMemoryPressure else {
            logger.debug("Skipping thumbnail cache due to memory pressure: \(url.lastPathComponent)")
            return
        }

        thumbnailCache.setObject(image, forKey: key, cost: cost)
        logger.debug("Cached gallery thumbnail: \(url.lastPathComponent) (\(self.formatBytes(cost)))")
    }

    /// Retrieve a cached thumbnail
    func getCachedThumbnail(for url: URL) -> NSImage? {
        // Try common thumbnail sizes
        for size in [150.0, 200.0, 256.0, 400.0] as [CGFloat] {
            let key = thumbnailKey(for: url, size: size)
            if let thumbnail = thumbnailCache.object(forKey: key) {
                logger.debug("Gallery thumbnail cache hit: \(url.lastPathComponent)")
                return thumbnail
            }
        }
        return nil
    }

    /// Retrieve thumbnail from disk cache or generate if needed (async)
    /// - Parameters:
    ///   - url: URL of the source image
    ///   - modificationDate: File modification date for cache invalidation
    /// - Returns: Thumbnail image (from disk cache or newly generated)
    func getThumbnailFromDisk(for url: URL, modificationDate: Date) async -> NSImage? {
        // Try disk cache first
        if let diskThumbnail = await thumbnailCacheManager.getThumbnail(for: url, modificationDate: modificationDate) {
            // Also cache in memory for faster subsequent access
            let key = thumbnailKey(for: url, size: 256)
            if !isUnderMemoryPressure {
                thumbnailCache.setObject(diskThumbnail, forKey: key, cost: estimateImageMemorySize(diskThumbnail))
            }
            return diskThumbnail
        }
        return nil
    }

    /// Preload thumbnails for gallery (batch operation using disk cache)
    func preloadGalleryThumbnails(_ imageFiles: [ImageFile]) async {
        await thumbnailCacheManager.preloadThumbnails(imageFiles, maxConcurrent: 4)
        logger.info("Preloaded \(imageFiles.count) gallery thumbnails")
    }

    /// Load or create a thumbnail, using cache if available
    func loadThumbnail(from url: URL, maxSize: CGFloat) async -> NSImage? {
        let key = thumbnailKey(for: url, size: maxSize)

        // Check cache first
        if let cached = thumbnailCache.object(forKey: key) {
            cacheHits += 1
            logger.debug("Thumbnail cache hit: \(url.lastPathComponent)")
            return cached
        }

        cacheMisses += 1

        // Load and resize on background queue
        return await withCheckedContinuation { continuation in
            backgroundQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                let targetSize = CGSize(width: maxSize, height: maxSize * 0.66)
                let thumbnail = self.createDownsampledThumbnail(from: url, targetSize: targetSize)

                Task { @MainActor in
                    if let thumbnail {
                        self.cacheThumbnail(thumbnail, for: url, size: maxSize)
                    }
                    continuation.resume(returning: thumbnail)
                }
            }
        }
    }

    /// Create a thumbnail key with size for cache differentiation
    private func thumbnailKey(for url: URL, size: CGFloat) -> NSString {
        return "\(url.absoluteString)_thumb_\(Int(size))" as NSString
    }

    /// Downsamples and center-crops an image from disk to a predictable thumbnail size to avoid letterboxing
    private func createDownsampledThumbnail(from url: URL, targetSize: CGSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Request a slightly larger thumbnail so we can crop to aspect-fill cleanly
            kCGImageSourceThumbnailMaxPixelSize: Int(max(targetSize.width, targetSize.height) * 1.5)
        ]

        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return makeAspectFillImage(from: cgThumb, targetSize: targetSize)
    }

    /// Produces an aspect-fill image cropped to the center for a given target size
    private func makeAspectFillImage(from cgImage: CGImage, targetSize: CGSize) -> NSImage? {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2
        )

        let output = NSImage(size: targetSize)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()

        NSImage(cgImage: cgImage, size: imageSize).draw(
            in: CGRect(origin: origin, size: scaledSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        output.unlockFocus()
        return output
    }

    /// Synchronous thumbnail creation for background queue
    private func createThumbnailSync(from image: NSImage, maxSize: CGFloat) -> NSImage? {
        let originalSize = image.size

        // If image is already smaller than max size, return original
        if originalSize.width <= maxSize && originalSize.height <= maxSize {
            return image
        }

        // Calculate scale factor to fit within maxSize
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height)
        let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)

        // Create new image with optimized size
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: originalSize),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }

    /// Performs intelligent cache optimization
    func optimizeCache() async {
        // Update memory pressure status
        updateMemoryPressureStatus()

        if isUnderMemoryPressure {
            await performAggressiveCleanup()
        } else {
            await performSmartEviction()
        }

        // Statistics are logged separately by timer
    }

    // MARK: - Private Optimization Methods

    /// Loads image with aggressive memory optimization
    private func loadImageOptimized(from url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }

        let imageSize = image.size
        let pixelCount = imageSize.width * imageSize.height

        // Much more aggressive downsampling for large images
        let maxPixels: CGFloat = 2_000_000 // Max 2MP for full cache
        let maxDimension: CGFloat = 2048 // Max 2K resolution

        if pixelCount > maxPixels || imageSize.width > maxDimension || imageSize.height > maxDimension {
            let targetPixels = min(maxPixels, pixelCount)
            let scale = sqrt(targetPixels / pixelCount)
            let newSize = CGSize(
                width: min(imageSize.width * scale, maxDimension),
                height: min(imageSize.height * scale, maxDimension)
            )

            return createDownsampledImage(from: image, targetSize: newSize)
        }

        return image
    }

    /// Creates optimized thumbnail for large images
    private func createThumbnail(from image: NSImage, maxSize: CGFloat = 300) -> NSImage? {
        let originalSize = image.size
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height)

        // Only create thumbnail if we can reduce size significantly
        guard scale < 0.8 else { return image }

        let thumbnailSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        return createDownsampledImage(from: image, targetSize: thumbnailSize)
    }

    /// Creates downsampled image to reduce memory usage
    private func createDownsampledImage(from image: NSImage, maxDimension: CGFloat? = nil, targetSize: CGSize? = nil) -> NSImage? {
        let originalSize = image.size

        let newSize: CGSize
        if let targetSize = targetSize {
            newSize = targetSize
        } else if let maxDim = maxDimension {
            let scale = min(maxDim / originalSize.width, maxDim / originalSize.height)
            newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        } else {
            return image
        }

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()

        return newImage
    }

    /// Determines cache priority with better differentiation
    private func determineCachePriority(url: URL, imageSize: CGSize) -> Int {
        var priority = 1

        let fileName = url.lastPathComponent.lowercased()
        let pixelCount = imageSize.width * imageSize.height

        // Size-based priority (larger = higher to avoid reloading cost)
        if pixelCount > 4_000_000 { priority += 3 } // > 4MP
        else if pixelCount > 2_000_000 { priority += 2 } // > 2MP
        else if pixelCount > 1_000_000 { priority += 1 } // > 1MP

        // File type hints
        if fileName.contains("preview") || fileName.contains("thumb") {
            priority += 2 // Previews are accessed frequently
        }

        if fileName.contains("current") || fileName.contains("active") {
            priority += 3 // Currently active wallpapers
        }

        return min(priority, 8) // Cap at 8 for better scoring range
    }

    /// Updates access metadata for cache management
    private func updateAccessMetadata(for key: NSString) {
        if let metadata = metadataCache.object(forKey: key) {
            metadata.updateAccess()
        }
    }

    /// Checks if cleanup is needed based on cache size and memory pressure
    private func shouldPerformCleanup() -> Bool {
        let currentSize = getCacheSize()
        let limit = maxCacheSize * 1024 * 1024

        return currentSize > Int(Double(limit) * 0.7) || isUnderMemoryPressure
    }

    /// Much more aggressive smart eviction
    private func performSmartEviction() async {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Get current memory usage
        let currentMemory = getCurrentMemoryUsage()
        let memoryLimitMB = maxCacheSize
        let memoryPressureLevel = Double(currentMemory) / Double(memoryLimitMB * 1024 * 1024) // Convert limit to bytes

        // Progressive cleanup based on memory pressure level
        let evictionPercentage: Double
        if memoryPressureLevel < 0.7 {
            // Low pressure - no cleanup needed
            logger.debug("Low memory pressure (\(String(format: "%.1f", memoryPressureLevel * 100))%) - no smart eviction needed.")
            return
        } else if memoryPressureLevel < 0.85 {
            // Moderate pressure - evict 20% (oldest/largest)
            evictionPercentage = 0.2
            logger.info("Moderate memory pressure (\(String(format: "%.1f", memoryPressureLevel * 100))%) - evicting 20% of cache")
        } else if memoryPressureLevel < 0.95 {
            // High pressure - evict 50%
            evictionPercentage = 0.5
            logger.warning("High memory pressure (\(String(format: "%.1f", memoryPressureLevel * 100))%) - evicting 50% of cache")
        } else {
            // Extreme pressure - clear all
            evictionPercentage = 1.0
            logger.error("Extreme memory pressure (\(String(format: "%.1f", memoryPressureLevel * 100))%) - clearing cache")
        }

        // Collect all cached entries with their metadata
        var entriesToEval: [(key: NSString, metadata: ImageMetadata)] = []
        for key in cachedImageKeys {
            if let metadata = metadataCache.object(forKey: key) {
                entriesToEval.append((key, metadata))
            }
        }

        guard !entriesToEval.isEmpty else { return }

        // Sort by retention score (lowest = should evict first)
        let sortedEntries = entriesToEval.sorted { $0.metadata.retentionScore < $1.metadata.retentionScore }

        // Calculate how many to evict
        let evictCount = Int(Double(sortedEntries.count) * evictionPercentage)
        let toEvict = Array(sortedEntries.prefix(evictCount))

        // Evict selected entries
        var freedMemory = 0
        for (key, metadata) in toEvict {
            imageCache.removeObject(forKey: key)
            thumbnailCache.removeObject(forKey: key)
            metadataCache.removeObject(forKey: key)
            cachedImageKeys.remove(key)
            freedMemory += metadata.fileSize
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Smart eviction completed: removed \(toEvict.count)/\(sortedEntries.count) entries, freed \(self.formatBytes(freedMemory)) in \(String(format: "%.3f", elapsed))s")
    }

    /// Get more accurate cache size estimation
    private func getActualCacheSize() -> Int {
        // Use NSCache's internal tracking for better accuracy
        let mainSize = min(imageCache.totalCostLimit, maxCacheSize * 1024 * 1024 / 2)
        let thumbSize = min(thumbnailCache.totalCostLimit, maxCacheSize * 1024 * 1024 / 4)
        return mainSize + thumbSize
    }

    /// Get current app memory usage
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

    /// Ultra-aggressive cleanup for memory pressure
    private func performAggressiveCleanup() async {
        logger.warning("AGGRESSIVE CLEANUP: Memory pressure detected")

        // Clear 90% of caches
        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        cachedImageKeys.removeAll()

        // Reset statistics
        cacheHits = 0
        cacheMisses = 0
        preloadRequests = 0

        // Drastically reduce cache limits
        imageCache.countLimit = 5
        imageCache.totalCostLimit = maxCacheSize * 1024 * 1024 / 10 // 10% of original

        thumbnailCache.countLimit = 10
        thumbnailCache.totalCostLimit = maxCacheSize * 1024 * 1024 / 20 // 5% of original

        isUnderMemoryPressure = true
        lastMemoryWarning = Date()

        // Longer cooldown period
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            self?.recoverFromMemoryPressure()
        }
    }

    /// Gradually recover cache limits after memory pressure
    private func recoverFromMemoryPressure() {
        logger.info("Recovering from memory pressure")

        // Gradually restore cache limits to 50% of original
        imageCache.countLimit = min(10, maxCacheSize / 8)
        imageCache.totalCostLimit = maxCacheSize * 1024 * 1024 / 4 // 25% of original

        thumbnailCache.countLimit = 25
        thumbnailCache.totalCostLimit = maxCacheSize * 1024 * 1024 / 8 // 12.5% of original

        isUnderMemoryPressure = false
    }

    /// Background cleanup when app is inactive
    private func performBackgroundCleanup() async {
        // Reduce cache limits when app is in background (silent operation)
        imageCache.countLimit = max(imageCache.countLimit / 2, 5)
        thumbnailCache.countLimit = max(thumbnailCache.countLimit / 2, 10)

        // Clear some cached content to free memory
        await performSmartEviction()
    }

    /// Preloads a batch of images using TaskGroup for structured concurrency
    private func preloadBatch(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask(priority: .utility) { [weak self] in
                    if let _ = await self?.preloadImage(from: url) {
                        self?.logger.debug("Preloaded: \(url.lastPathComponent)")
                    }
                }
            }
        }
    }

    /// Updates memory pressure status based on system conditions
    private func updateMemoryPressureStatus() {
        // Simple heuristic: if last memory warning was recent, consider under pressure
        let timeSinceLastWarning = Date().timeIntervalSince(lastMemoryWarning)
        isUnderMemoryPressure = timeSinceLastWarning < memoryWarningCooldown
    }

    /// Enhanced memory size estimation with validation
    private func estimateImageMemorySize(_ image: NSImage) -> Int {
        let size = image.size

        guard size.width.isFinite && size.height.isFinite &&
              size.width > 0 && size.height > 0 &&
              size.width < 50000 && size.height < 50000 else {
            return 1024 * 1024 // 1MB default for invalid dimensions
        }

        let width = Int(size.width)
        let height = Int(size.height)

        guard width > 0 && height > 0 && width < 50000 && height < 50000 else {
            return 1024 * 1024
        }

        // More accurate estimation: RGBA + potential compression
        let bytesPerPixel = 4 // RGBA
        let estimatedSize = width * height * bytesPerPixel

        // Cap at reasonable maximum
        return min(estimatedSize, 100 * 1024 * 1024)
    }


}

// MARK: - Performance Monitoring

extension ImageCacheService {
    /// Comprehensive cache statistics
    struct CacheStatistics {
        let hitRate: Double
        let totalRequests: Int
        let currentSize: Int
        let formattedSize: String
        let preloadRequests: Int
        let isUnderPressure: Bool
    }

    /// Gets detailed cache statistics
    func getCacheStatistics() -> CacheStatistics {
        let totalRequests = cacheHits + cacheMisses
        let hitRate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0
        let currentSize = getCacheSize()

        return CacheStatistics(
            hitRate: hitRate,
            totalRequests: totalRequests,
            currentSize: currentSize,
            formattedSize: formatBytes(currentSize),
            preloadRequests: preloadRequests,
            isUnderPressure: isUnderMemoryPressure
        )
    }

    /// Logs detailed cache performance metrics
    func logCacheStatistics() {
        let stats = getCacheStatistics()

        // Only log if there's meaningful activity or issues
        if stats.totalRequests > 0 || stats.isUnderPressure {
            logger.info("Cache stats - Hit rate: \(String(format: "%.1f", stats.hitRate * 100))%, Size: \(stats.formattedSize), Requests: \(stats.totalRequests), Preloads: \(stats.preloadRequests)")
        }

        // Update performance monitor with cache hit rate
        PerformanceMonitor.shared.updateCacheHitRate(stats.hitRate)
    }

    /// Resets performance counters
    func resetStatistics() {
        cacheHits = 0
        cacheMisses = 0
        preloadRequests = 0
        logger.debug("Cache statistics reset")
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}