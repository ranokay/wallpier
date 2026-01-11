import Foundation

public enum WallpaperServiceError: LocalizedError {
    case permissionDenied
    case invalidImage(URL)
    case screenNotFound
    case operationFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "System denied permission to change wallpaper."
        case .invalidImage(let url):
            return "The image at \(url.lastPathComponent) is not a valid wallpaper."
        case .screenNotFound:
            return "The target screen could not be found."
        case .operationFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

public enum ImageScannerError: LocalizedError {
    case folderNotAccessible(URL)
    case cancelled
    case unsupportedFormat(URL)
    case operationFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .folderNotAccessible(let url):
            return "The folder \(url.path) is not accessible."
        case .cancelled:
            return "The scan was cancelled."
        case .unsupportedFormat(let url):
            return "Unsupported image format: \(url.lastPathComponent)."
        case .operationFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

public enum ImageCacheError: LocalizedError {
    case outOfMemory
    case operationFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .outOfMemory:
            return "Not enough memory to cache image."
        case .operationFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

public enum FileMonitorError: LocalizedError {
    case monitoringNotSupported
    case operationFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .monitoringNotSupported:
            return "File monitoring is not supported for this location."
        case .operationFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}
