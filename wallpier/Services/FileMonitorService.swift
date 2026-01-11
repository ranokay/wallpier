//
//  FileMonitorService.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation
import OSLog

// Note: FileMonitorServiceProtocol and FileMonitorDelegate are defined in Utilities/Protocols.swift

/// Service responsible for monitoring file system changes
final class FileMonitorService: NSObject, FileMonitorServiceProtocol {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "FileMonitorService")

    /// Delegate for monitoring events
    weak var delegate: FileMonitorDelegate?

    /// The URL being monitored
    private var monitoredURL: URL?

    /// File descriptor for the monitored directory
    private var fileDescriptor: Int32 = -1

    /// Dispatch source for file system events
    private var dispatchSource: DispatchSourceFileSystemObject?

    /// Queue for file monitoring operations
    private let monitorQueue = DispatchQueue(label: "com.oxystack.wallpier.filemonitor", qos: .utility)

    /// Callback closure for file changes
    private var changeCallback: (() -> Void)?

    deinit {
        stopMonitoring()
    }

    /// Starts monitoring a directory for changes
    func startMonitoring(_ url: URL, callback: @escaping () -> Void) throws {
        logger.info("Starting file monitoring for: \(url.path)")

        // Stop any existing monitoring
        stopMonitoring()

        // Validate directory exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("Directory not found: \(url.path)")
            throw WallpaperError.folderNotFound
        }

        // Open file descriptor for the directory
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.error("Failed to open file descriptor for: \(url.path)")
            throw WallpaperError.permissionDenied
        }

        // Create dispatch source for file system events
        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke, .link],
            queue: monitorQueue
        )

        guard let source = dispatchSource else {
            close(fileDescriptor)
            fileDescriptor = -1
            logger.error("Failed to create dispatch source")
            throw WallpaperError.systemIntegrationFailed
        }

        // Store references
        monitoredURL = url
        changeCallback = callback

        // Set event handler
        source.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }

        // Set cancellation handler
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        // Activate the source
        source.activate()

        logger.info("File monitoring started for: \(url.path)")
    }

    /// Stops monitoring the current directory
    func stopMonitoring() {
        guard isMonitoring() else { return }

        logger.info("Stopping file monitoring")

        // Cancel dispatch source
        dispatchSource?.cancel()
        dispatchSource = nil

        // Clean up
        monitoredURL = nil
        changeCallback = nil

        logger.info("File monitoring stopped")
    }

    /// Returns whether monitoring is currently active
    func isMonitoring() -> Bool {
        return dispatchSource != nil && monitoredURL != nil
    }

    /// Handles file system events
    private func handleFileSystemEvent() {
        guard let monitoredURL = monitoredURL else { return }

        logger.debug("File system change detected in: \(monitoredURL.path)")

        // Debounce rapid changes
        debounceFileSystemChanges {
            // Call the callback on main queue
            Task { @MainActor in
                self.changeCallback?()
                if let delegate = self.delegate {
                    Task {
                        await delegate.fileMonitorDidDetectChanges(self, in: monitoredURL)
                    }
                }
            }
        }
    }

    /// Debounces file system changes to avoid excessive callbacks
    private func debounceFileSystemChanges(action: @escaping () -> Void) {
        // Cancel any pending work
        NSObject.cancelPreviousPerformRequests(withTarget: self)

        // Schedule new work with delay
        perform(#selector(executeDebounced), with: action, afterDelay: 0.5)
    }

    /// Executes debounced action
    @objc private func executeDebounced(_ action: @escaping () -> Void) {
        action()
    }
}

/// Extensions for advanced monitoring features
extension FileMonitorService {
    /// Monitors multiple directories simultaneously
    func startMonitoringMultipleDirectories(_ urls: [URL], callback: @escaping (URL) -> Void) throws {
        // For now, we'll only monitor the first directory
        // A full implementation would create multiple monitors
        guard let firstURL = urls.first else {
            throw WallpaperError.folderNotFound
        }

        try startMonitoring(firstURL) {
            callback(firstURL)
        }

        logger.info("Monitoring \(urls.count) directories (simplified to first)")
    }

    /// Gets information about the monitored directory
    func getMonitoringInfo() -> (url: URL?, isActive: Bool, duration: TimeInterval?) {
        return (
            url: monitoredURL,
            isActive: isMonitoring(),
            duration: nil // Could track start time to calculate duration
        )
    }

    /// Validates if a directory can be monitored
    func canMonitor(_ url: URL) -> Bool {
        // Check if directory exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Check if we can open the directory
        let fd = open(url.path, O_EVTONLY)
        if fd >= 0 {
            close(fd)
            return true
        }

        return false
    }
}

/// Error handling extension
extension FileMonitorService {
    /// Handles monitoring errors gracefully
    private func handleMonitoringError(_ error: Error) {
        logger.error("File monitoring error: \(error.localizedDescription)")

        // Stop monitoring on error
        stopMonitoring()

        // Notify delegate
        Task { @MainActor in
            if let delegate = self.delegate {
                Task {
                    await delegate.fileMonitorDidFailWithError(self, error: error)
                }
            }
        }
    }

    /// Recovers from monitoring failures by restarting
    func recoverFromFailure() {
        guard let url = monitoredURL, let callback = changeCallback else {
            logger.warning("Cannot recover - no previous monitoring configuration")
            return
        }

        logger.info("Attempting to recover file monitoring")

        do {
            try startMonitoring(url, callback: callback)
            logger.info("File monitoring recovery successful")
        } catch {
            logger.error("File monitoring recovery failed: \(error.localizedDescription)")
            handleMonitoringError(error)
        }
    }
}