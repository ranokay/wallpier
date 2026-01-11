import Foundation
import SwiftUI
import OSLog

// MARK: - Error Severity

/// Severity level for presented errors
enum ErrorSeverity: Sendable {
    case error      // Critical error (red)
    case warning    // Important warning (yellow)
    case info       // Informational message (blue)

    var color: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }

    var iconName: String {
        switch self {
        case .error:
            return "exclamationmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}

// MARK: - Presented Error

/// Error formatted for user presentation
struct PresentedError: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
    let recoverySuggestion: String?
    let severity: ErrorSeverity
    let errorCode: String?
    let canRetry: Bool

    // Note: Can't store closure in Sendable type, will handle retry differently

    init(
        title: String,
        message: String,
        recoverySuggestion: String? = nil,
        severity: ErrorSeverity = .error,
        errorCode: String? = nil,
        canRetry: Bool = false
    ) {
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.severity = severity
        self.errorCode = errorCode
        self.canRetry = canRetry
    }
}

// MARK: - Error Presenter

/// Service for centralized error presentation
@MainActor
final class ErrorPresenter: ObservableObject {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "ErrorPresenter")

    // MARK: - Published Properties

    /// Currently displayed error
    @Published var currentError: PresentedError?

    /// Whether error banner is visible
    @Published var showError: Bool = false

    /// Error history for debugging
    @Published private(set) var errorHistory: [PresentedError] = []

    // MARK: - Configuration

    /// Maximum number of errors to keep in history
    private let maxHistoryCount = 50

    /// Auto-dismiss duration for info/warning messages
    private let autoDismissDuration: TimeInterval = 5.0

    /// Current auto-dismiss task
    private var autoDismissTask: Task<Void, Never>?

    // MARK: - Error Presentation

    /// Presents an error to the user
    func present(_ error: Error, context: String? = nil, canRetry: Bool = false) {
        let presentedError = convertToPresentedError(error, context: context, canRetry: canRetry)
        present(presentedError)
    }

    /// Presents a custom error
    func present(_ error: PresentedError) {
        // Cancel any pending auto-dismiss
        autoDismissTask?.cancel()

        // Set current error
        currentError = error
        showError = true

        // Add to history
        errorHistory.append(error)
        if errorHistory.count > maxHistoryCount {
            errorHistory.removeFirst()
        }

        // Log error
        logError(error)

        // Auto-dismiss for non-critical errors
        if error.severity != .error {
            autoDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(autoDismissDuration * 1_000_000_000))
                if self.currentError?.id == error.id {
                    self.dismiss()
                }
            }
        }
    }

    /// Presents a warning message
    func presentWarning(_ message: String, title: String = "Warning") {
        let error = PresentedError(
            title: title,
            message: message,
            severity: .warning
        )
        present(error)
    }

    /// Presents an informational message
    func presentInfo(_ message: String, title: String = "Info") {
        let error = PresentedError(
            title: title,
            message: message,
            severity: .info
        )
        present(error)
    }

    /// Dismisses the current error
    func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        showError = false

        // Clear after animation completes
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            if !showError {
                currentError = nil
            }
        }
    }

    /// Clears error history
    func clearHistory() {
        errorHistory.removeAll()
        logger.info("Error history cleared")
    }

    // MARK: - Error Conversion

    private func convertToPresentedError(_ error: Error, context: String?, canRetry: Bool) -> PresentedError {
        // Handle LocalizedError
        if let localizedError = error as? LocalizedError {
            return PresentedError(
                title: context ?? "Error",
                message: localizedError.errorDescription ?? error.localizedDescription,
                recoverySuggestion: localizedError.recoverySuggestion,
                severity: .error,
                errorCode: errorCodeForError(error),
                canRetry: canRetry
            )
        }

        // Handle specific error types
        switch error {
        case let wallpaperError as WallpaperError:
            return presentedErrorForWallpaperError(wallpaperError, context: context, canRetry: canRetry)
        case let scanError as ScanError:
            return presentedErrorForScanError(scanError, context: context, canRetry: canRetry)
        case let cacheError as CacheError:
            return presentedErrorForCacheError(cacheError, context: context, canRetry: canRetry)
        default:
            // Generic error
            return PresentedError(
                title: context ?? "Error",
                message: error.localizedDescription,
                recoverySuggestion: "Please try again or contact support if the problem persists.",
                severity: .error,
                errorCode: errorCodeForError(error),
                canRetry: canRetry
            )
        }
    }

    private func presentedErrorForWallpaperError(_ error: WallpaperError, context: String?, canRetry: Bool) -> PresentedError {
        PresentedError(
            title: context ?? "Wallpaper Error",
            message: error.errorDescription ?? "An unknown wallpaper error occurred.",
            recoverySuggestion: error.recoverySuggestion,
            severity: .error,
            errorCode: errorCodeForWallpaperError(error),
            canRetry: canRetry
        )
    }

    private func presentedErrorForScanError(_ error: ScanError, context: String?, canRetry: Bool) -> PresentedError {
        PresentedError(
            title: context ?? "Scan Error",
            message: error.errorDescription ?? "An unknown scan error occurred.",
            recoverySuggestion: error.recoverySuggestion,
            severity: .error,
            errorCode: errorCodeForScanError(error),
            canRetry: canRetry
        )
    }

    private func presentedErrorForCacheError(_ error: CacheError, context: String?, canRetry: Bool) -> PresentedError {
        PresentedError(
            title: context ?? "Cache Error",
            message: error.errorDescription ?? "An unknown cache error occurred.",
            recoverySuggestion: error.recoverySuggestion,
            severity: .warning, // Cache errors are warnings, not critical
            errorCode: errorCodeForCacheError(error),
            canRetry: canRetry
        )
    }

    // MARK: - Error Codes

    private func errorCodeForError(_ error: Error) -> String? {
        if error is WallpaperError {
            return errorCodeForWallpaperError(error as! WallpaperError)
        } else if error is ScanError {
            return errorCodeForScanError(error as! ScanError)
        } else if error is CacheError {
            return errorCodeForCacheError(error as! CacheError)
        }
        return nil
    }

    private func errorCodeForWallpaperError(_ error: WallpaperError) -> String {
        switch error {
        case .permissionDenied:
            return "W001"
        case .invalidImageFormat:
            return "W002"
        case .folderNotFound:
            return "W003"
        case .systemIntegrationFailed:
            return "W004"
        case .fileNotFound:
            return "W005"
        case .unsupportedImageType:
            return "W006"
        case .noAvailableScreens:
            return "W007"
        case .setWallpaperFailed:
            return "W008"
        }
    }

    private func errorCodeForScanError(_ error: ScanError) -> String {
        switch error {
        case .folderNotAccessible:
            return "S001"
        case .noImagesFound:
            return "S002"
        case .cancelled:
            return "S003"
        case .underlying:
            return "S004"
        }
    }

    private func errorCodeForCacheError(_ error: CacheError) -> String {
        switch error {
        case .imageLoadFailed:
            return "C001"
        case .cacheFull:
            return "C002"
        case .invalidImageData:
            return "C003"
        }
    }

    // MARK: - Logging

    private func logError(_ error: PresentedError) {
        let codeStr = error.errorCode.map { " [\($0)]" } ?? ""
        logger.error("Error\(codeStr): \(error.message)")

        if let suggestion = error.recoverySuggestion {
            logger.info("Recovery suggestion: \(suggestion)")
        }
    }
}
