import Foundation

// MARK: - Retry Utility

/// Utility for retrying operations with exponential backoff
struct RetryUtility {
    /// Maximum number of retry attempts
    static let defaultMaxAttempts = 3

    /// Base delay between retries (seconds)
    static let defaultBaseDelay: TimeInterval = 1.0

    /// Executes an operation with retry logic and exponential backoff
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (including initial attempt)
    ///   - baseDelay: Base delay in seconds between retries
    ///   - shouldRetry: Optional closure to determine if error is retryable
    ///   - operation: The async throwing operation to retry
    /// - Returns: The result of the operation
    /// - Throws: The last error if all attempts fail
    static func withRetry<T>(
        maxAttempts: Int = defaultMaxAttempts,
        baseDelay: TimeInterval = defaultBaseDelay,
        shouldRetry: ((Error) -> Bool)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var attempt = 1

        while attempt <= maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Check if we should retry this error
                if let shouldRetry = shouldRetry, !shouldRetry(error) {
                    throw error
                }

                // If this was the last attempt, throw the error
                if attempt >= maxAttempts {
                    throw error
                }

                // Calculate exponential backoff delay
                let delay = baseDelay * Double(attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                attempt += 1
            }
        }

        // This should never be reached, but satisfy compiler
        throw lastError ?? NSError(domain: "RetryUtility", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown retry error"])
    }

    /// Determines if an error is typically worth retrying
    static func isRetryableError(_ error: Error) -> Bool {
        // File system errors that might be transient
        if let nsError = error as NSError? {
            switch nsError.code {
            case NSFileReadNoSuchFileError,
                 NSFileReadNoPermissionError:
                return false // These won't fix themselves with retry
            case NSFileReadUnknownError,
                 NSFileReadCorruptFileError:
                return true // These might be transient
            default:
                break
            }
        }

        // WallpaperError - some are retryable
        if let wallpaperError = error as? WallpaperError {
            switch wallpaperError {
            case .fileNotFound, .folderNotFound, .permissionDenied:
                return false // Won't fix with retry
            case .systemIntegrationFailed, .setWallpaperFailed:
                return true // Might be transient
            default:
                return false
            }
        }

        // CacheError - mostly retryable
        if error is CacheError {
            return true
        }

        // ScanError - some are retryable
        if let scanError = error as? ScanError {
            switch scanError {
            case .cancelled, .folderNotAccessible:
                return false
            case .noImagesFound, .underlying:
                return true
            }
        }

        // Default: consider it retryable
        return true
    }
}

// MARK: - Convenience Extensions

extension Task where Failure == Error {
    /// Creates a task that automatically retries on failure
    static func retrying(
        maxAttempts: Int = RetryUtility.defaultMaxAttempts,
        baseDelay: TimeInterval = RetryUtility.defaultBaseDelay,
        operation: @escaping () async throws -> Success
    ) -> Task<Success, Failure> {
        Task {
            try await RetryUtility.withRetry(
                maxAttempts: maxAttempts,
                baseDelay: baseDelay,
                operation: operation
            )
        }
    }
}
