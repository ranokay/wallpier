//
//  SystemService.swift
//  wallpier
//
//  System integration service for managing permissions, startup behavior, and macOS integration
//

import Foundation
import AppKit
import ServiceManagement
import OSLog

/// Protocol defining system integration capabilities
protocol SystemServiceProtocol {
    /// Request necessary permissions for the app
    func requestPermissions() async -> Bool

    /// Check if launch at startup is enabled
    var isLaunchAtStartupEnabled: Bool { get }

    /// Enable or disable launch at startup
    func setLaunchAtStartup(_ enabled: Bool) async -> Bool

    /// Check current permission status
    nonisolated func checkPermissionStatus() -> PermissionStatus

    /// Hide dock icon for menu bar only operation
    nonisolated func configureDockVisibility(_ visible: Bool)

    /// Handle app state changes
    nonisolated func handleAppStateChange(_ state: AppState)
}

/// System permission status
enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
    case partiallyGranted(granted: [String], denied: [String])

    var isFullyGranted: Bool {
        switch self {
        case .granted:
            return true
        default:
            return false
        }
    }
}

/// Application state for lifecycle management
enum AppState {
    case launching
    case active
    case background
    case terminating
}

/// System integration service implementation
@MainActor
@preconcurrency class SystemService: ObservableObject, SystemServiceProtocol {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "SystemService")

    @Published var permissionStatus: PermissionStatus = .notDetermined
    @Published var isDockHidden: Bool = false
    @Published var currentAppState: AppState = .launching

    init() {
        setupNotificationObservers()
        let _ = self.checkPermissionStatus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Permission Management

    func requestPermissions() async -> Bool {
        logger.info("Requesting system permissions")

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let openPanel = NSOpenPanel()
                openPanel.title = "Grant File Access"
                openPanel.message = "To cycle wallpapers, Wallpier needs access to your image folders. Please select a folder containing images."
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.allowsMultipleSelection = false
                openPanel.canCreateDirectories = false

                // Start in Pictures directory if possible
                let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                openPanel.directoryURL = picturesURL

                openPanel.begin { response in
                    if response == .OK {
                        // User selected a folder, which grants access
                        self.logger.info("User granted folder access")
                        self.permissionStatus = .granted
                        continuation.resume(returning: true)
                    } else {
                        // User cancelled
                        self.logger.info("User cancelled folder access request")
                        self.permissionStatus = .denied
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    nonisolated func checkPermissionStatus() -> PermissionStatus {
        // For sandboxed apps, we consider permissions granted if:
        // 1. The user has previously selected folders (which gives us access to those folders)
        // 2. The app can read its own bundle and basic system info

        // Check if we can read basic app information
        let canReadAppBundle = true // Bundle.main.bundleURL is always non-nil for a running app bundle

        if canReadAppBundle {
            logger.debug("Basic app permissions confirmed")

            // In a sandboxed environment, file access is granted per-folder by user selection
            // We'll consider this "granted" since the user will select folders as needed
            self.permissionStatus = .granted

            return .granted
        } else {
            logger.warning("Cannot read basic app information")

            self.permissionStatus = .denied

            return .denied
        }
    }

    // MARK: - Launch at Startup

    var isLaunchAtStartupEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS versions
            return checkLegacyLaunchAtStartup()
        }
    }

    func setLaunchAtStartup(_ enabled: Bool) async -> Bool {
        logger.info("Setting launch at startup: \(enabled)")

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try await SMAppService.mainApp.register()
                    logger.info("Successfully registered for launch at startup")
                } else {
                    try await SMAppService.mainApp.unregister()
                    logger.info("Successfully unregistered from launch at startup")
                }
                return true
            } catch {
                logger.error("Failed to set launch at startup: \(error.localizedDescription)")
                return false
            }
        } else {
            // Fallback for older macOS versions
            return setLegacyLaunchAtStartup(enabled)
        }
    }

            private func checkLegacyLaunchAtStartup() -> Bool {
        // For macOS < 13.0, return false as we'll focus on the modern API
        // The legacy LSSharedFileList API is deprecated and complex to implement correctly
        logger.info("Legacy launch at startup check not implemented - using modern API only")
        return false
    }

            private func setLegacyLaunchAtStartup(_ enabled: Bool) -> Bool {
        // For macOS < 13.0, return false as we'll focus on the modern API
        // The legacy LSSharedFileList API is deprecated and complex to implement correctly
        logger.warning("Legacy launch at startup setting not implemented - modern API required")
        return false
    }

    // MARK: - Dock Visibility

    nonisolated func configureDockVisibility(_ visible: Bool) {
        logger.info("Configuring dock visibility: \(visible)")

        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        NSApp.setActivationPolicy(policy)

        self.isDockHidden = !visible
    }

    // MARK: - App State Management

        nonisolated func handleAppStateChange(_ state: AppState) {
        logger.debug("App state changed to: \(String(describing: state))")

        self.currentAppState = state

        switch state {
        case .launching:
            // Setup launch behavior
            break
        case .active:
            // Handle becoming active
            break
        case .background:
            // Handle going to background
            break
        case .terminating:
            // Cleanup before termination
            cleanup()
        }
    }

    // MARK: - Notification Setup

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        Task { await self.handleAppStateChange(.active) }
    }

    @objc private func appDidResignActive() {
        Task { await self.handleAppStateChange(.background) }
    }

    @objc private func appWillTerminate() {
        Task { await self.handleAppStateChange(.terminating) }
    }

    // MARK: - Cleanup

    private func cleanup() {
        logger.info("Performing system service cleanup")
        // Perform any necessary cleanup before app termination
    }
}

// MARK: - Permission Helper Extensions

extension SystemService {
    /// Show a user-friendly permission request dialog
    func showPermissionRequestDialog() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Wallpier needs access to your image folders"
        alert.informativeText = "To cycle through your wallpapers, Wallpier needs permission to access the folders containing your images. You can grant this by selecting your image folder in the next step."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    /// Show launch at startup configuration dialog
    func showLaunchAtStartupDialog() -> Bool? {
        let alert = NSAlert()
        alert.messageText = "Start Wallpier automatically when you log in?"
        alert.informativeText = "This will allow Wallpier to start cycling your wallpapers as soon as you log in to your Mac."
        alert.addButton(withTitle: "Yes, start automatically")
        alert.addButton(withTitle: "No, I'll start it manually")
        alert.addButton(withTitle: "Ask me later")
        alert.alertStyle = .informational

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            return false
        default:
            return nil
        }
    }
}

// MARK: - System Integration Helpers

extension SystemService {
    /// Get system information for troubleshooting
    func getSystemInfo() -> [String: Any] {
        return [
            "macOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "Unknown",
            "permissionStatus": String(describing: permissionStatus),
            "launchAtStartup": isLaunchAtStartupEnabled,
            "dockHidden": isDockHidden,
            "appState": String(describing: currentAppState)
        ]
    }
}
