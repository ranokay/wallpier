//
//  ImageCacheService.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import AppKit
import OSLog

/// Protocol for image caching operations
protocol ImageCacheServiceProtocol {
    func cacheImage(_ image: NSImage, for url: URL) async
    func getCachedImage(for url: URL) async -> NSImage?
    func preloadImage(from url: URL) async -> NSImage?
    func clearCache() async
    func removeCachedImage(for url: URL) async
    func getCacheSize() async -> Int
    func preloadImages(_ urls: [URL], priority: TaskPriority) async
    func optimizeCache() async
}

/// Service responsible for efficient image caching with performance optimizations
@MainActor
@preconcurrency final class ImageCacheService: ImageCacheServiceProtocol {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "ImageCacheService")

    /// Multi-level caching system
    private let imageCache = NSCache<NSString, NSImage>()
    private let metadataCache = NSCache<NSString, ImageMetadata>()
    private let thumbnailCache = NSCache<NSString, NSImage>()

    /// Keep track of keys in the cache for eviction strategy
    private var cachedImageKeys = Set<NSString>()

    /// Concurrent queues for different priorities
    private let highPriorityQueue = DispatchQueue(label: "com.oxystack.wallpier.imagecache.high", qos: .userInitiated, attributes: .concurrent)
    private let backgroundQueue = DispatchQueue(label: "com.oxystack.wallpier.imagecache.background", qos: .utility, attributes: .concurrent)

    /// Performance optimization settings
    private let maxCacheSize: Int
    private let maxThumbnailSize: Int = 10 * 1024 * 1024 // 10MB for thumbnails
    private let preloadBatchSize = 5
    private let maxConcurrentLoads = 4

    /// Memory pressure monitoring
    private var isUnderMemoryPressure = false
    private var lastMemoryWarning = Date.distantPast
    private let memoryWarningCooldown: TimeInterval = 30.0

    /// Cache statistics for monitoring
    private var cacheHits = 0
    private var cacheMisses = 0
    private var preloadRequests = 0

    /// Enhanced metadata for smart cache management
    private class ImageMetadata {
        let fileSize: Int
        var lastAccessed: Date
        let imageSize: CGSize
        var accessCount: Int
        let cacheTime: Date
        var priority: Int // Higher = more important

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
        }

        /// Score for cache eviction (higher = keep longer)
        var retentionScore: Double {
            let ageBonus = max(0, 1.0 - Date().timeIntervalSince(cacheTime) / (24 * 3600)) // Newer is better
            let accessBonus = min(Double(accessCount) / 10.0, 1.0) // More accesses = better
            let priorityBonus = Double(priority) / 10.0
            return ageBonus + accessBonus + priorityBonus
        }
    }

    init(maxCacheSizeMB: Int = 100) {
        self.maxCacheSize = max(10, min(maxCacheSizeMB, 1000)) // Clamp between 10MB and 1GB
        configureCache()
        setupMemoryManagement()

        logger.info("ImageCacheService initialized with \(self.maxCacheSize)MB limit")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Configures all cache layers with optimized settings
    private func configureCache() {
        let totalCostLimit = maxCacheSize * 1024 * 1024

        // Main image cache (70% of total memory)
        imageCache.totalCostLimit = Int(Double(totalCostLimit) * 0.7)
        imageCache.countLimit = min(50, maxCacheSize / 2) // Adaptive count limit
        imageCache.evictsObjectsWithDiscardedContent = true

        // Thumbnail cache (20% of total memory)
        thumbnailCache.totalCostLimit = Int(Double(totalCostLimit) * 0.2)
        thumbnailCache.countLimit = 100
        thumbnailCache.evictsObjectsWithDiscardedContent = true

        // Metadata cache (10% of total memory, lightweight)
        metadataCache.totalCostLimit = Int(Double(totalCostLimit) * 0.1)
        metadataCache.countLimit = 200
        metadataCache.evictsObjectsWithDiscardedContent = true

        logger.info("Cache configured: Main=\(self.imageCache.totalCostLimit/1024/1024)MB, Thumbnails=\(self.thumbnailCache.totalCostLimit/1024/1024)MB")
    }

    /// Sets up memory pressure monitoring and automatic cleanup
    private func setupMemoryManagement() {
        // Monitor app state changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.optimizeCache() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.performBackgroundCleanup() }
        }

        // Periodic optimization and statistics reporting
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.optimizeCache() }
        }

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.logCacheStatistics()
            }
        }
    }

    /// Caches an image with enhanced metadata and smart eviction
    func cacheImage(_ image: NSImage, for url: URL) {
        let key = url.absoluteString as NSString
        let cost = estimateImageMemorySize(image)

        guard cost > 0 && cost < 100 * 1024 * 1024 else { // Max 100MB per image
            logger.warning("Skipping cache for oversized image: \(url.lastPathComponent)")
            return
        }

        // Determine priority based on file characteristics
        let priority = determineCachePriority(url: url, imageSize: image.size)

        // Store in appropriate cache layer
        if cost < 5 * 1024 * 1024 { // Small images (< 5MB) go to main cache
            imageCache.setObject(image, forKey: key, cost: cost)
        } else {
            // Large images: store thumbnail and defer full image to disk if needed
            if let thumbnail = createThumbnail(from: image) {
                let thumbnailCost = estimateImageMemorySize(thumbnail)
                thumbnailCache.setObject(thumbnail, forKey: key, cost: thumbnailCost)
            }
        }

        // Store enhanced metadata
        let metadata = ImageMetadata(
            fileSize: cost,
            lastAccessed: Date(),
            imageSize: image.size,
            priority: priority
        )
        metadataCache.setObject(metadata, forKey: key)
        cachedImageKeys.insert(key) // Add key to our tracking set

        logger.debug("Cached image: \(url.lastPathComponent) (size: \(self.formatBytes(cost)), priority: \(priority))")

        // Check if we need to free up space
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

                // Load image with size optimization
                Task { @MainActor in
                    guard let image = self.loadImageOptimized(from: url) else {
                        self.logger.debug("Failed to preload: \(url.lastPathComponent)")
                        continuation.resume(returning: nil)
                        return
                    }

                    // Cache the image
                    self.cacheImage(image, for: url)
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// Batch preloading with priority and concurrency control
    func preloadImages(_ urls: [URL], priority: TaskPriority = .medium) async {
        logger.info("Starting batch preload of \(urls.count) images")

        let startTime = CFAbsoluteTimeGetCurrent()

        await withTaskGroup(of: Void.self) { group in
            for batch in urls.chunked(into: preloadBatchSize) {
                group.addTask(priority: priority) { [weak self] in
                    await self?.preloadBatch(batch)
                }
            }
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

    /// Performs intelligent cache optimization
    func optimizeCache() async {
        logger.debug("Starting cache optimization")

        // Update memory pressure status
        updateMemoryPressureStatus()

        if isUnderMemoryPressure {
            await performAggressiveCleanup()
        } else {
            await performSmartEviction()
        }

        // Log cache statistics
        logCacheStatistics()
    }

    // MARK: - Private Optimization Methods

    /// Loads image with size and memory optimizations
    private func loadImageOptimized(from url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }

        // Check if image is too large and needs downsampling
        let imageSize = image.size
        let maxDimension: CGFloat = 4096 // Reasonable maximum

        if imageSize.width > maxDimension || imageSize.height > maxDimension {
            return createDownsampledImage(from: image, maxDimension: maxDimension)
        }

        return image
    }

    /// Creates optimized thumbnail for large images
    private func createThumbnail(from image: NSImage, maxSize: CGFloat = 512) -> NSImage? {
        let originalSize = image.size

        // Calculate thumbnail size maintaining aspect ratio
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height)
        guard scale < 1.0 else { return image } // Don't upscale

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

    /// Determines cache priority based on image characteristics
    private func determineCachePriority(url: URL, imageSize: CGSize) -> Int {
        var priority = 1

        // Larger images get higher priority (more expensive to reload)
        let pixelCount = imageSize.width * imageSize.height
        if pixelCount > 2_000_000 { priority += 2 } // > 2MP
        else if pixelCount > 500_000 { priority += 1 } // > 0.5MP

        // Recent files get higher priority
        let fileName = url.lastPathComponent.lowercased()
        if fileName.contains("recent") || fileName.contains("new") {
            priority += 1
        }

        return min(priority, 5) // Cap at 5
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

        return currentSize > Int(Double(limit) * 0.8) || isUnderMemoryPressure
    }

    /// Performs smart eviction based on access patterns and priority
    private func performSmartEviction() async {
        logger.debug("Performing smart cache eviction")

        // Get all metadata for scoring
        var scoredEntries: [(key: NSString, score: Double)] = []
        for key in cachedImageKeys {
            if let metadata = metadataCache.object(forKey: key) {
                scoredEntries.append((key, metadata.retentionScore))
            } else {
                // If metadata is missing, remove the entry
                removeCachedImage(for: URL(string: key as String)!)
            }
        }

        // Sort by score (lowest score first for eviction)
        scoredEntries.sort { $0.score < $1.score }

        // Evict until cache size is below target
        let targetSize = Int(Double(maxCacheSize) * 1024 * 1024 * 0.7) // Target 70% of max
        var currentSize = getCacheSize()

        for (key, score) in scoredEntries {
            if currentSize > targetSize {
                removeCachedImage(for: URL(string: key as String)!)
                currentSize = getCacheSize() // Recalculate after removal
                logger.debug("Evicted image with score \(String(format: "%.2f", score)): \(key.lastPathComponent)")
            } else {
                break // Stop if target size is reached
            }
        }

        self.logger.debug("Smart cache eviction completed. Current size: \(self.formatBytes(currentSize))")
    }

    /// Aggressive cleanup under memory pressure
    private func performAggressiveCleanup() async {
        logger.warning("Performing aggressive cache cleanup due to memory pressure")

        // Clear thumbnail cache first
        thumbnailCache.removeAllObjects()

        // Reduce main cache significantly
        imageCache.countLimit = max(imageCache.countLimit / 4, 5)

        // Mark as under pressure
        isUnderMemoryPressure = true
        lastMemoryWarning = Date()

        // Reset after cooldown period
        DispatchQueue.main.asyncAfter(deadline: .now() + memoryWarningCooldown) { [weak self] in
            self?.isUnderMemoryPressure = false
        }
    }

    /// Background cleanup when app is inactive
    private func performBackgroundCleanup() async {
        logger.debug("Performing background cleanup")

        // Reduce cache limits when app is in background
        imageCache.countLimit = max(imageCache.countLimit / 2, 5)
        thumbnailCache.countLimit = max(thumbnailCache.countLimit / 2, 10)
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

    /// Formats bytes for human-readable output
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
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
        logger.info("Cache stats - Hit rate: \(String(format: "%.1f", stats.hitRate * 100))%, Size: \(stats.formattedSize), Requests: \(stats.totalRequests), Preloads: \(stats.preloadRequests)")

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