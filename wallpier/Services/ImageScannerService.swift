//
//  ImageScannerService.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import OSLog
import UniformTypeIdentifiers

// Note: ImageScannerServiceProtocol is defined in Utilities/Protocols.swift

/// Service responsible for scanning directories for image files with performance optimizations
actor ImageScannerService: ImageScannerServiceProtocol {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "ImageScannerService")
    private let fileManager = FileManager.default

    /// Supported image file extensions and MIME types
    private let supportedImageTypes = ["jpg", "jpeg", "png", "heic", "bmp", "tiff", "gif", "webp"]
    private let supportedUTTypes: [UTType] = [.jpeg, .png, .heic, .bmp, .tiff, .gif, .webP]

    /// Performance optimization constants
    private let batchSize = 50 // Process files in batches for better memory usage
    private let progressUpdateInterval = 25 // Update progress every N files
    private let maxConcurrentOperations = 4 // Limit concurrent file operations

    /// Simple cache for recently validated files to avoid redundant checks
    private var validationCache: [String: Bool] = [:]
    private let maxCacheSize = 1000

    /// Scans a single directory (non-recursive) with performance optimization
    func scanDirectory(_ url: URL) async throws -> [ImageFile] {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("Starting optimized directory scan: \(url.path)")

        guard fileManager.fileExists(atPath: url.path) else {
            logger.error("Directory not found: \(url.path)")
            throw WallpaperError.folderNotFound
        }

        do {
            // Get directory contents with only essential properties
            let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )

            // Pre-filter by extension before expensive validation
            let potentialImageFiles = contents.filter { fileURL in
                quickExtensionCheck(fileURL)
            }

            // Process in batches for memory efficiency
            var imageFiles: [ImageFile] = []
            imageFiles.reserveCapacity(potentialImageFiles.count) // Pre-allocate capacity

            for batch in potentialImageFiles.chunked(into: batchSize) {
                let batchResults = await processBatch(batch)
                imageFiles.append(contentsOf: batchResults)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("Directory scan completed: \(imageFiles.count) images found in \(String(format: "%.3f", elapsed))s")

            return imageFiles
        } catch {
            logger.error("Failed to scan directory: \(error.localizedDescription)")
            throw error
        }
    }

    /// High-performance recursive directory scan with optimizations
    func scanDirectoryRecursively(_ url: URL, progress: @escaping (Int) -> Void) async throws -> [ImageFile] {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("Starting optimized recursive scan: \(url.path)")

        guard fileManager.fileExists(atPath: url.path) else {
            logger.error("Directory not found: \(url.path)")
            throw WallpaperError.folderNotFound
        }

        do {
            var imageFiles: [ImageFile] = []
            var processedCount = 0

            // Use DirectoryEnumerator for memory-efficient traversal
            let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { [self] url, error in
                    self.logger.warning("Enumeration error at \(url.path): \(error.localizedDescription)")
                    return true // Continue enumeration
                }
            ) else {
                throw WallpaperError.folderNotFound
            }

            // Process files in batches for memory efficiency
            var batch: [URL] = []
            batch.reserveCapacity(batchSize)

            // Convert to async sequence for safe iteration
            let urls = enumerator.compactMap { $0 as? URL }

            for fileURL in urls {
                processedCount += 1

                // Quick extension check before expensive operations
                if quickExtensionCheck(fileURL) {
                    batch.append(fileURL)
                }

                // Process batch when full or update progress
                if batch.count >= batchSize {
                    let batchResults = await processBatch(batch)
                    imageFiles.append(contentsOf: batchResults)
                    batch.removeAll(keepingCapacity: true)
                }

                // Update progress periodically
                if processedCount % progressUpdateInterval == 0 {
                    let currentCount = processedCount // Capture local value
                    Task { @MainActor in
                        progress(currentCount)
                    }
                }

                // Allow other operations periodically
                if processedCount % 100 == 0 {
                    await Task.yield()
                }
            }

            // Process remaining batch
            if !batch.isEmpty {
                let finalBatchResults = await processBatch(batch)
                imageFiles.append(contentsOf: finalBatchResults)
            }

            // Final progress update
            let finalCount = processedCount // Capture local value
            Task { @MainActor in
                progress(finalCount)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("Recursive scan completed: \(imageFiles.count) images from \(processedCount) files in \(String(format: "%.3f", elapsed))s")

            return imageFiles
        } catch {
            logger.error("Failed to scan directory recursively: \(error.localizedDescription)")
            throw error
        }
    }

    /// Quick scan with limited depth for faster results
    func quickScanDirectory(_ url: URL, maxDepth: Int = 2) async throws -> [ImageFile] {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("Starting quick scan with max depth \(maxDepth): \(url.path)")

        guard fileManager.fileExists(atPath: url.path) else {
            throw WallpaperError.folderNotFound
        }

        let imageFiles = try await scanWithDepthLimit(url, currentDepth: 0, maxDepth: maxDepth)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Quick scan completed: \(imageFiles.count) images in \(String(format: "%.3f", elapsed))s")

        return imageFiles
    }

    /// Validates if a file is a supported image type (optimized version)
    nonisolated func validateImageFile(_ url: URL) -> Bool {
        return quickExtensionCheck(url)
    }

    // MARK: - Private Optimization Methods

    /// Quick extension-based validation without file system calls
    nonisolated private func quickExtensionCheck(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return supportedImageTypes.contains(fileExtension)
    }

    /// Optimized image file validation with caching
    private func validateImageFileOptimized(_ url: URL) async -> Bool {
        let path = url.path

        // Check cache first
        if let cached = validationCache[path] {
            return cached
        }

        // Quick extension check
        guard quickExtensionCheck(url) else {
            updateValidationCache(path, result: false)
            return false
        }

        // Check if it's a regular file (using cached resource values if available)
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            let isRegularFile = resourceValues.isRegularFile ?? false

            updateValidationCache(path, result: isRegularFile)
            return isRegularFile
        } catch {
            updateValidationCache(path, result: false)
            return false
        }
    }

        /// Simple cache update with size management
    private func updateValidationCache(_ path: String, result: Bool) {
        // Clean cache if it gets too large
        if validationCache.count >= maxCacheSize {
            // Remove oldest entries (simple LRU approximation)
            let keysToRemove = Array(validationCache.keys.prefix(maxCacheSize / 4))
            for key in keysToRemove {
                validationCache.removeValue(forKey: key)
            }
        }

        validationCache[path] = result
    }

    /// Optimized ImageFile creation with minimal file system calls
    private func createImageFileOptimized(from url: URL) async -> ImageFile? {
        do {
            // Get all required resource values in one call
            let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))

            return ImageFile(
                url: url,
                name: url.lastPathComponent,
                size: resourceValues.fileSize ?? 0,
                modificationDate: resourceValues.contentModificationDate ?? Date(),
                pathExtension: url.pathExtension.lowercased()
            )
        } catch {
            logger.error("Failed to create ImageFile for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Process a batch of URLs efficiently using TaskGroup for concurrency
    private func processBatch(_ urls: [URL]) async -> [ImageFile] {
        var results: [ImageFile] = []
        await withTaskGroup(of: ImageFile?.self) { group in
            for url in urls {
                group.addTask { [weak self] in
                    guard let self = self else { return nil }
                    guard await self.validateImageFileOptimized(url) else { return nil }
                    return await self.createImageFileOptimized(from: url)
                }
            }
            for await imageFile in group {
                if let imageFile = imageFile {
                    results.append(imageFile)
                }
            }
        }
        return results
    }

    /// Scan with depth limitation for performance
    private func scanWithDepthLimit(_ url: URL, currentDepth: Int, maxDepth: Int) async throws -> [ImageFile] {
        guard currentDepth <= maxDepth else { return [] }

        var results: [ImageFile] = []

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        // Process files first
        let files = contents.filter { quickExtensionCheck($0) }
        let fileResults = await processBatch(files)
        results.append(contentsOf: fileResults)

        // Process subdirectories if we haven't reached max depth
        if currentDepth < maxDepth {
            let directories = contents.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            }

            for directory in directories {
                do {
                    let subResults = try await scanWithDepthLimit(directory, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                    results.append(contentsOf: subResults)
                } catch {
                    logger.warning("Failed to scan subdirectory \(directory.path): \(error.localizedDescription)")
                }
            }
        }

        return results
    }
}

// MARK: - Performance Utilities
// Note: Array extension for chunked(into:) is defined in ImageCacheService.swift

// MARK: - Performance Monitoring Extension

extension ImageScannerService {
    /// Clears the validation cache to free memory
    func clearValidationCache() {
        validationCache.removeAll()
        logger.debug("Validation cache cleared")
    }

    /// Gets cache statistics for monitoring
    func getCacheStatistics() -> (entries: Int, memoryEstimate: Int) {
        let entries = validationCache.count
        let memoryEstimate = entries * 64 // Rough estimate: 64 bytes per entry
        return (entries: entries, memoryEstimate: memoryEstimate)
    }
}