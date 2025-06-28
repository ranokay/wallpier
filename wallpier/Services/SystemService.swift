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
import Combine

/// Protocol defining system integration capabilities
@MainActor
protocol SystemServiceProtocol: Sendable {
    /// Request necessary permissions for the app
    func requestPermissions() async -> Bool

    /// Check if launch at startup is enabled
    var isLaunchAtStartupEnabled: Bool { get }

    /// Enable or disable launch at startup
    func setLaunchAtStartup(_ enabled: Bool) async -> Bool

    /// Check current permission status
    func checkPermissionStatus() -> PermissionStatus

    /// Hide dock icon for menu bar only operation
    func configureDockVisibility(_ visible: Bool)

    /// Handle app state changes
    func handleAppStateChange(_ state: AppState)
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
class SystemService: NSObject, SystemServiceProtocol, ObservableObject {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "SystemService")

    @Published var permissionStatus: PermissionStatus = .notDetermined
    @Published var isDockHidden: Bool = false
    @Published var currentAppState: AppState = .launching
    @Published var isLaunchAtStartupEnabled: Bool = false

    override init() {
        super.init()
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
            Task { @MainActor in
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

    func checkPermissionStatus() -> PermissionStatus {
        // In a sandboxed environment, we assume permissions are granted by folder selection
        logger.debug("Permission status: granted by default")
        self.permissionStatus = .granted
        return .granted
    }

    // MARK: - Launch at Startup

    func setLaunchAtStartup(_ enabled: Bool) async -> Bool {
        logger.info("Setting launch at startup: \(enabled)")

        return await withCheckedContinuation { continuation in
            Task {
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try await SMAppService.mainApp.unregister()
                    }
                    await MainActor.run {
                        self.isLaunchAtStartupEnabled = enabled
                    }
                    continuation.resume(returning: true)
                } catch {
                    await MainActor.run {
                        self.logger.error("Failed to update launch at startup setting: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Dock Visibility

    func configureDockVisibility(_ visible: Bool) {
        logger.info("Configuring dock visibility: \(visible)")
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        self.isDockHidden = !visible
    }

    // MARK: - App State Management

    func handleAppStateChange(_ state: AppState) {
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
        // Handle app becoming active directly
        self.handleAppStateChange(.active)
    }

    @objc private func appDidResignActive() {
        // Handle app resigning active directly
        self.handleAppStateChange(.background)
    }

    @objc private func appWillTerminate() {
        // Handle app termination directly
        self.handleAppStateChange(.terminating)
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
