import Foundation

// MARK: - Scan Errors

/// Errors that can occur during folder scanning operations
enum ScanError: LocalizedError {
    case folderNotAccessible(URL)
    case noImagesFound(URL)
    case cancelled
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .folderNotAccessible(let url):
            return "The folder \(url.path) is not accessible."
        case .noImagesFound(let url):
            return "No images were found in \(url.lastPathComponent)."
        case .cancelled:
            return "The scan was cancelled."
        case .underlying(let error):
            return error.localizedDescription
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .folderNotAccessible:
            return "Try selecting a different folder or check folder permissions."
        case .noImagesFound:
            return "Select a folder containing supported image files (JPEG, PNG, HEIC, etc.)."
        case .cancelled:
            return "Start the scan again when ready."
        case .underlying:
            return "Try again or select a different folder."
        }
    }
}

// MARK: - Wallpaper Errors

/// Errors that can occur when setting wallpapers
/// This is the single source of truth for all wallpaper-related errors
enum WallpaperError: LocalizedError {
    case permissionDenied
    case invalidImageFormat
    case folderNotFound
    case systemIntegrationFailed
    case fileNotFound
    case unsupportedImageType
    case noAvailableScreens
    case setWallpaperFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission denied to set wallpaper."
        case .invalidImageFormat:
            return "The selected image format is not supported."
        case .folderNotFound:
            return "The specified folder could not be found."
        case .systemIntegrationFailed:
            return "Failed to integrate with system wallpaper settings."
        case .fileNotFound:
            return "Image file not found"
        case .unsupportedImageType:
            return "Unsupported image format"
        case .noAvailableScreens:
            return "No displays available - please connect a display"
        case .setWallpaperFailed(let underlying):
            return "Failed to set wallpaper: \(underlying.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please grant necessary permissions in System Settings > Privacy & Security."
        case .invalidImageFormat, .unsupportedImageType:
            return "Use a supported format: JPEG, PNG, HEIC, BMP, TIFF, or GIF."
        case .folderNotFound, .fileNotFound:
            return "Verify the file exists and select a valid folder."
        case .systemIntegrationFailed:
            return "Try restarting the application or your Mac."
        case .noAvailableScreens:
            return "Ensure at least one display is connected."
        case .setWallpaperFailed:
            return "Try selecting a different image or restart the application."
        }
    }
}

// MARK: - Cache Errors

/// Errors that can occur during image caching operations
enum CacheError: LocalizedError {
    case imageLoadFailed(URL)
    case cacheFull
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let url):
            return "Failed to load image from \(url.lastPathComponent)."
        case .cacheFull:
            return "Image cache is full."
        case .invalidImageData:
            return "The image data is invalid or corrupted."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .imageLoadFailed:
            return "Verify the image file is not corrupted."
        case .cacheFull:
            return "Clear the cache in Settings > Advanced."
        case .invalidImageData:
            return "Try a different image file."
        }
    }
}
