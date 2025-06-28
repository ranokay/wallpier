//
//  StatusMenuView.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI
import AppKit

/// Menu bar status item controller for wallpaper app
@MainActor
class StatusMenuController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var wallpaperViewModel: WallpaperViewModel?
    private var settingsViewModel: SettingsViewModel?

    @Published var isMenuVisible = false

    init() {
        setupStatusItem()
    }

    deinit {
        // Clean up status item
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func setViewModels(wallpaper: WallpaperViewModel, settings: SettingsViewModel) {
        self.wallpaperViewModel = wallpaper
        self.settingsViewModel = settings
        updateStatusItemAppearance()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let statusButton = statusItem?.button {
            statusButton.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Wallpier")
            statusButton.action = #selector(statusItemClicked)
            statusButton.target = self
            statusButton.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Add tooltip
            statusButton.toolTip = "Wallpier - Wallpaper Cycling"
        }

        // Setup menu
        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // App Title
        let titleItem = NSMenuItem(title: "Wallpier", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Status Section
        let status = getCurrentStatus()
        let statusDisplayItem = NSMenuItem(title: "Status: \(status.isRunning ? "Running" : "Stopped")", action: nil, keyEquivalent: "")
        statusDisplayItem.isEnabled = false
        menu.addItem(statusDisplayItem)

        let imageCountItem = NSMenuItem(title: "\(status.imageCount) images found", action: nil, keyEquivalent: "")
        imageCountItem.isEnabled = false
        menu.addItem(imageCountItem)

        menu.addItem(NSMenuItem.separator())

        // Quick Controls
        let startStopItem = NSMenuItem(
            title: status.isRunning ? "Stop Cycling" : "Start Cycling",
            action: status.isRunning ? #selector(stopCycling) : #selector(startCycling),
            keyEquivalent: ""
        )
        startStopItem.target = self
        menu.addItem(startStopItem)

        let nextItem = NSMenuItem(title: "Next Image", action: #selector(nextImage), keyEquivalent: "")
        nextItem.target = self
        nextItem.isEnabled = status.isRunning
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(title: "Previous Image", action: #selector(previousImage), keyEquivalent: "")
        prevItem.target = self
        prevItem.isEnabled = status.isRunning
        menu.addItem(prevItem)

        menu.addItem(NSMenuItem.separator())

        // Current Image Info
        if let currentImage = status.currentImage {
            let currentImageItem = NSMenuItem(title: "Current: \(currentImage)", action: nil, keyEquivalent: "")
            currentImageItem.isEnabled = false
            menu.addItem(currentImageItem)
        } else {
            let noImageItem = NSMenuItem(title: "No image selected", action: nil, keyEquivalent: "")
            noImageItem.isEnabled = false
            menu.addItem(noImageItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Settings and Quit
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let openMainItem = NSMenuItem(title: "Open Wallpier", action: #selector(openMainWindow), keyEquivalent: "")
        openMainItem.target = self
        menu.addItem(openMainItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Wallpier", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func updateStatusItemAppearance() {
        guard let statusButton = statusItem?.button,
              let wallpaperViewModel = wallpaperViewModel else { return }

        // Update icon based on running state
        let iconName = wallpaperViewModel.isRunning ? "photo.on.rectangle.angled" : "photo.on.rectangle.angled"
        statusButton.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Wallpier")

        // Update tooltip
        let status = wallpaperViewModel.isRunning ? "Running" : "Stopped"
        let imageCount = wallpaperViewModel.foundImages.count
        statusButton.toolTip = "Wallpier - \(status) (\(imageCount) images)"
    }

    func removeStatusItem() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        isMenuVisible.toggle()
    }

    @objc private func openSettings() {
        // Post notification to open settings
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @objc private func openMainWindow() {
        // Post notification to open main window
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Public Interface

    @objc func startCycling() {
        Task { await wallpaperViewModel?.startCycling() }
        updateStatusItemAppearance()
    }

    @objc func stopCycling() {
        wallpaperViewModel?.stopCycling()
        updateStatusItemAppearance()
    }

    @objc func nextImage() {
        wallpaperViewModel?.goToNextImage()
    }

    @objc func previousImage() {
        wallpaperViewModel?.goToPreviousImage()
    }

    func getCurrentStatus() -> (isRunning: Bool, currentImage: String?, imageCount: Int, statusMessage: String) {
        guard let viewModel = wallpaperViewModel else {
            return (false, nil, 0, "Not initialized")
        }

        return (
            isRunning: viewModel.isRunning,
            currentImage: viewModel.currentImage?.name,
            imageCount: viewModel.foundImages.count,
            statusMessage: viewModel.statusMessage
        )
    }
}

// MARK: - Menu Management
extension StatusMenuController {
    /// Updates the menu items based on current state
    func updateMenu() {
        setupMenu()
    }
}

// MARK: - SwiftUI Integration

struct StatusMenuView: View {
    @StateObject private var controller = StatusMenuController()
    let wallpaperViewModel: WallpaperViewModel
    let settingsViewModel: SettingsViewModel

    var body: some View {
        EmptyView()
            .onAppear {
                controller.setViewModels(wallpaper: wallpaperViewModel, settings: settingsViewModel)
            }
            .onDisappear {
                controller.removeStatusItem()
            }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openMainWindow = Notification.Name("openMainWindow")
    static let appWillTerminate = Notification.Name("appWillTerminate")
}

#Preview {
    StatusMenuView(
        wallpaperViewModel: WallpaperViewModel(),
        settingsViewModel: SettingsViewModel(settings: WallpaperSettings())
    )
}