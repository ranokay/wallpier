//
//  ImageFile.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import AppKit

/// Represents an image file with metadata
struct ImageFile: Codable, Identifiable, Hashable, Sendable {
    /// Unique identifier for the image file
    let id = UUID()

    /// File URL
    let url: URL

    /// Display name of the file
    let name: String

    /// File size in bytes
    let size: Int

    /// Last modification date
    let modificationDate: Date

    /// File extension (lowercase)
    let pathExtension: String

    /// Relative path from the root scan directory (for organization)
    let relativePath: String?

    /// Whether the file is currently accessible
    var isAccessible: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Human-readable file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// File creation for Codable
    init(url: URL, name: String, size: Int, modificationDate: Date, pathExtension: String, relativePath: String? = nil) {
        self.url = url
        self.name = name
        self.size = size
        self.modificationDate = modificationDate
        self.pathExtension = pathExtension.lowercased()
        self.relativePath = relativePath
    }

    /// Convenience initializer from URL
    init?(from url: URL, relativeTo baseURL: URL? = nil) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isRegularFileKey
            ])

            guard let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile else {
                return nil
            }

            let relativePath: String?
            if let baseURL = baseURL {
                relativePath = url.path.replacingOccurrences(of: baseURL.path + "/", with: "")
            } else {
                relativePath = nil
            }

            self.init(
                url: url,
                name: url.lastPathComponent,
                size: resourceValues.fileSize ?? 0,
                modificationDate: resourceValues.contentModificationDate ?? Date(),
                pathExtension: url.pathExtension,
                relativePath: relativePath
            )
        } catch {
            return nil
        }
    }

    // MARK: - Codable Implementation

    enum CodingKeys: String, CodingKey {
        case url
        case name
        case size
        case modificationDate
        case pathExtension
        case relativePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(Int.self, forKey: .size)
        modificationDate = try container.decode(Date.self, forKey: .modificationDate)
        pathExtension = try container.decode(String.self, forKey: .pathExtension)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encode(modificationDate, forKey: .modificationDate)
        try container.encode(pathExtension, forKey: .pathExtension)
        try container.encodeIfPresent(relativePath, forKey: .relativePath)
    }

    // MARK: - Hashable Implementation

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(modificationDate)
    }

    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        return lhs.url == rhs.url && lhs.modificationDate == rhs.modificationDate
    }
}

// MARK: - Extensions

extension ImageFile {
    /// Returns the directory containing this image file
    var parentDirectory: URL {
        return url.deletingLastPathComponent()
    }

    /// Returns the image dimensions if available (requires loading the image)
    func getImageDimensions() async -> CGSize? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let image = NSImage(contentsOf: self.url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image.size)
            }
        }
    }

    /// Validates that the file still exists and is accessible
    func validate() -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Gets file metadata with error handling
    static func createSafely(from url: URL, relativeTo baseURL: URL? = nil) -> ImageFile? {
        do {
            // Check if file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            // Get resource values
            let resourceValues = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isRegularFileKey,
                .isReadableKey
            ])

            // Validate it's a readable regular file
            guard let isRegularFile = resourceValues.isRegularFile,
                  let isReadable = resourceValues.isReadable,
                  isRegularFile && isReadable else {
                return nil
            }

            // Calculate relative path
            let relativePath: String?
            if let baseURL = baseURL {
                relativePath = String(url.path.dropFirst(baseURL.path.count + 1))
            } else {
                relativePath = nil
            }

            return ImageFile(
                url: url,
                name: url.lastPathComponent,
                size: resourceValues.fileSize ?? 0,
                modificationDate: resourceValues.contentModificationDate ?? Date(),
                pathExtension: url.pathExtension,
                relativePath: relativePath
            )

        } catch {
            return nil
        }
    }
}

// MARK: - Collection Extensions

extension Array where Element == ImageFile {
    /// Filters out inaccessible image files
    func filterAccessible() -> [ImageFile] {
        return filter { $0.isAccessible }
    }

    /// Sorts images by modification date (newest first)
    func sortedByDate() -> [ImageFile] {
        return sorted { $0.modificationDate > $1.modificationDate }
    }

    /// Sorts images by name alphabetically
    func sortedByName() -> [ImageFile] {
        return sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Sorts images by file size (largest first)
    func sortedBySize() -> [ImageFile] {
        return sorted { $0.size > $1.size }
    }

    /// Groups images by their parent directory
    func groupedByDirectory() -> [URL: [ImageFile]] {
        return Dictionary(grouping: self) { $0.parentDirectory }
    }

    /// Returns total size of all image files
    var totalSize: Int {
        return reduce(0) { $0 + $1.size }
    }

    /// Returns formatted total size
    var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}