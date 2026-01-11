//
//  ThumbnailCacheManager.swift
//  wallpier
//
//  Manages persistent disk-based thumbnail cache for instant gallery loading
//

import Foundation
import AppKit
import OSLog
import CryptoKit

/// Manages disk-based thumbnail caching for fast gallery loads
actor ThumbnailCacheManager {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "ThumbnailCacheManager")

    // MARK: - Cache Directory

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    // MARK: - Configuration

    private let thumbnailSize: CGFloat = 256
    private let maxCacheSize: Int = 100 * 1024 * 1024 // 100MB max
    private let maxThumbnailAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    // MARK: - Initialization

    init() {
        // Use system cache directory
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            // This should never happen on macOS - caches directory always exists
            fatalError("Unable to access system caches directory - this indicates a serious system configuration issue")
        }

        self.cacheDirectory = cachesURL.appendingPathComponent("com.oxystack.wallpier/thumbnails", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        logger.info("ThumbnailCacheManager initialized at: \(self.cacheDirectory.path)")

        // Perform initial cleanup
        Task {
            await self.cleanupOldThumbnails()
        }
    }

    // MARK: - Public Interface

    /// Retrieves a cached thumbnail or generates and caches a new one
    /// - Parameters:
    ///   - imageURL: URL of the source image
    ///   - modificationDate: Modification date of the source file (for cache invalidation)
    /// - Returns: Cached or newly generated thumbnail
    func getThumbnail(for imageURL: URL, modificationDate: Date) async -> NSImage? {
        let cacheKey = generateCacheKey(for: imageURL, modificationDate: modificationDate)
        let thumbnailURL = cacheDirectory.appendingPathComponent(cacheKey)

        // Check if cached thumbnail exists and is valid
        if fileManager.fileExists(atPath: thumbnailURL.path) {
            if let cachedImage = await loadThumbnailFromDisk(at: thumbnailURL) {
                logger.debug("Cache hit for thumbnail: \(imageURL.lastPathComponent)")
                return cachedImage
            }
        }

        // Generate new thumbnail
        logger.debug("Cache miss for thumbnail: \(imageURL.lastPathComponent), generating...")
        guard let thumbnail = await generateThumbnail(from: imageURL) else {
            return nil
        }

        // Save to disk cache
        await saveThumbnailToDisk(thumbnail, at: thumbnailURL)

        return thumbnail
    }

    /// Preloads thumbnails for multiple images in parallel
    /// - Parameters:
    ///   - imageFiles: Array of ImageFile objects to preload
    ///   - maxConcurrent: Maximum number of concurrent operations
    func preloadThumbnails(_ imageFiles: [ImageFile], maxConcurrent: Int = 4) async {
        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0

            for imageFile in imageFiles {
                // Limit concurrency
                if activeCount >= maxConcurrent {
                    await group.next()
                    activeCount -= 1
                }

                group.addTask { [weak self] in
                    _ = await self?.getThumbnail(for: imageFile.url, modificationDate: imageFile.modificationDate)
                }
                activeCount += 1
            }
        }

        logger.info("Preloaded thumbnails for \(imageFiles.count) images")
    }

    /// Clears the entire thumbnail cache
    func clearCache() async {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
            logger.info("Thumbnail cache cleared")
        } catch {
            logger.error("Failed to clear thumbnail cache: \(error.localizedDescription)")
        }
    }

    /// Gets the current cache size in bytes
    func getCacheSize() async -> Int {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            let totalSize = contents.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return total + size
            }
            return totalSize
        } catch {
            return 0
        }
    }

    // MARK: - Private Implementation

    /// Generates a unique cache key based on file URL and modification date
    private func generateCacheKey(for url: URL, modificationDate: Date) -> String {
        let path = url.path
        let timestamp = Int(modificationDate.timeIntervalSince1970)
        let input = "\(path)-\(timestamp)"

        // Use SHA256 hash for cache key
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    /// Generates a thumbnail from the source image
    private func generateThumbnail(from url: URL) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = NSImage(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }

                let thumbnail = self.createThumbnailSync(from: image, maxSize: self.thumbnailSize)
                continuation.resume(returning: thumbnail)
            }
        }
    }

    /// Creates a thumbnail synchronously (must be called on background queue)
    nonisolated private func createThumbnailSync(from image: NSImage, maxSize: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let scale = min(maxSize / width, maxSize / height)
        let newWidth = width * scale
        let newHeight = height * scale

        let thumbnail = NSImage(size: NSSize(width: newWidth, height: newHeight))
        thumbnail.lockFocus()

        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high

        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect(x: 0, y: 0, width: width, height: height),
            operation: .copy,
            fraction: 1.0
        )

        thumbnail.unlockFocus()
        return thumbnail
    }

    /// Saves a thumbnail to disk as JPEG
    private func saveThumbnailToDisk(_ image: NSImage, at url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                    continuation.resume()
                    return
                }

                do {
                    try jpegData.write(to: url, options: .atomic)
                } catch {
                    self.logger.error("Failed to save thumbnail: \(error.localizedDescription)")
                }

                continuation.resume()
            }
        }
    }

    /// Loads a thumbnail from disk
    private func loadThumbnailFromDisk(at url: URL) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(contentsOf: url)
                continuation.resume(returning: image)
            }
        }
    }

    /// Cleans up old and large cache files
    private func cleanupOldThumbnails() async {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )

            let now = Date()
            var currentSize = 0
            var filesToRemove: [URL] = []

            // Sort by creation date (oldest first)
            let sortedFiles = contents.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 < date2
            }

            for fileURL in sortedFiles {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let creationDate = resourceValues?.creationDate ?? Date.distantPast
                let fileSize = resourceValues?.fileSize ?? 0

                currentSize += fileSize

                // Remove if too old or cache is too large
                if now.timeIntervalSince(creationDate) > maxThumbnailAge || currentSize > maxCacheSize {
                    filesToRemove.append(fileURL)
                }
            }

            // Remove old files
            for fileURL in filesToRemove {
                try? fileManager.removeItem(at: fileURL)
            }

            if !filesToRemove.isEmpty {
                logger.info("Cleaned up \(filesToRemove.count) old thumbnails")
            }
        } catch {
            logger.error("Failed to cleanup thumbnails: \(error.localizedDescription)")
        }
    }
}
