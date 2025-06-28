//
//  StatusMenuView.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI
import AppKit
import Combine

/// Enhanced menu bar status item controller for wallpaper app
@MainActor
class StatusMenuController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var wallpaperViewModel: WallpaperViewModel?
    private var settingsViewModel: SettingsViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var menuUpdateTimer: Timer?

    @Published var isMenuVisible = false

    init() {
        setupStatusItem()
        startMenuUpdateTimer()
    }

    deinit {
        // Clean up
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        cancellables.removeAll()
    }

    func setViewModels(wallpaper: WallpaperViewModel, settings: SettingsViewModel) {
        self.wallpaperViewModel = wallpaper
        self.settingsViewModel = settings

        // Setup reactive bindings
        setupBindings()
        updateStatusItemAppearance()
        updateMenu()
    }

    private func setupBindings() {
        guard let wallpaperViewModel = wallpaperViewModel else { return }

        // Update menu when wallpaper state changes
        wallpaperViewModel.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
                self?.updateMenu()
            }
            .store(in: &cancellables)

        wallpaperViewModel.$currentImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)

        wallpaperViewModel.$foundImages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
                self?.updateMenu()
            }
            .store(in: &cancellables)

        // Note: canStartCycling is a computed property, so we observe its dependencies instead

        // Observe hasError for status icon updates
        wallpaperViewModel.$hasError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
                self?.updateMenu()
            }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let statusButton = statusItem?.button {
            statusButton.image = createStatusIcon(isRunning: false, hasError: false)
            statusButton.action = #selector(statusItemClicked)
            statusButton.target = self
            statusButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusButton.toolTip = "Wallpier - Click to open menu"

            // Add subtle animation for running state
            statusButton.imageScaling = .scaleProportionallyUpOrDown
        }
    }

    private func createStatusIcon(isRunning: Bool, hasError: Bool) -> NSImage? {
        let iconName: String
        if hasError {
            iconName = "exclamationmark.triangle"
        } else if isRunning {
            iconName = "photo.on.rectangle.angled"
        } else {
            iconName = "photo.on.rectangle.angled"
        }

        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Wallpier")

        // Add color tinting for different states
        if let image = image {
            image.isTemplate = true
            if hasError {
                // Red tint for errors
                let tintedImage = NSImage(size: image.size)
                tintedImage.lockFocus()
                NSColor.systemRed.set()
                image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
                tintedImage.unlockFocus()
                return tintedImage
            } else if isRunning {
                // Green tint for running
                let tintedImage = NSImage(size: image.size)
                tintedImage.lockFocus()
                NSColor.systemGreen.set()
                image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
                tintedImage.unlockFocus()
                return tintedImage
            }
        }

        return image
    }

    private func startMenuUpdateTimer() {
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if self?.isMenuVisible == true {
                    self?.updateMenu()
                }
            }
        }
    }

    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
    }

    private func updateStatusItemAppearance() {
        guard let statusButton = statusItem?.button,
              let wallpaperViewModel = wallpaperViewModel else { return }

        let hasError = wallpaperViewModel.hasError
        let isRunning = wallpaperViewModel.isRunning

        statusButton.image = createStatusIcon(isRunning: isRunning, hasError: hasError)

        // Enhanced tooltip with current status
        let status = getCurrentStatus()
        let folderName = wallpaperViewModel.selectedFolderPath?.lastPathComponent ?? "No folder"
        let tooltipText = """
            Wallpier - \(isRunning ? "Running" : "Stopped")
            \(status.imageCount) images in \(folderName)
            \(status.currentImage ?? "No current image")
            """
        statusButton.toolTip = tooltipText
    }

    func removeStatusItem() {
        stopMenuUpdateTimer()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Enhanced Menu Creation

    private func updateMenu() {
        let menu = NSMenu()
        let status = getCurrentStatus()

        // Header Section with App Icon and Name
        addHeaderSection(to: menu, status: status)

        // Status Information Section
        addStatusSection(to: menu, status: status)

        // Quick Controls Section
        addControlsSection(to: menu, status: status)

        // Current Image Information
        addImageInfoSection(to: menu, status: status)

        // Quick Actions
        addQuickActionsSection(to: menu, status: status)

        // Performance & Debug Info (when running)
        if status.isRunning {
            addPerformanceSection(to: menu, status: status)
        }

        // Main Actions
        addMainActionsSection(to: menu)

        statusItem?.menu = menu
    }

    private func addHeaderSection(to menu: NSMenu, status: StatusInfo) {
        // App title with icon
        let titleItem = NSMenuItem(title: "  Wallpier", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let appIcon = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil) {
            appIcon.size = NSSize(width: 16, height: 16)
            titleItem.image = appIcon
        }
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())
    }

    private func addStatusSection(to menu: NSMenu, status: StatusInfo) {
        // Status with colored indicator - ensure we get the latest state
        let currentStatus = getCurrentStatus()
        let statusText = currentStatus.isRunning ? "🟢 Running" : "⚫ Stopped"
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // Folder information
        let folderName = wallpaperViewModel?.selectedFolderPath?.lastPathComponent ?? "No folder selected"
        let folderItem = NSMenuItem(title: "📁 \(folderName)", action: nil, keyEquivalent: "")
        folderItem.isEnabled = false
        menu.addItem(folderItem)

        // Image count with icon
        let imageCountText = "🖼️ \(status.imageCount) images found"
        let imageCountItem = NSMenuItem(title: imageCountText, action: nil, keyEquivalent: "")
        imageCountItem.isEnabled = false
        menu.addItem(imageCountItem)

        // Multi-monitor info
        if let wallpaperVM = wallpaperViewModel, wallpaperVM.availableScreens.count > 1 {
            let screenCount = wallpaperVM.availableScreens.count
            let multiMonitorItem = NSMenuItem(title: "🖥️ \(screenCount) monitors detected", action: nil, keyEquivalent: "")
            multiMonitorItem.isEnabled = false
            menu.addItem(multiMonitorItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addControlsSection(to menu: NSMenu, status: StatusInfo) {
        // Create inline control view
        let controlView = createInlineControlView(status: status)
        let controlMenuItem = NSMenuItem()
        controlMenuItem.view = controlView
        menu.addItem(controlMenuItem)

        menu.addItem(NSMenuItem.separator())
    }

    private func createInlineControlView(status: StatusInfo) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 32))

        // Previous button
        let prevButton = NSButton(frame: NSRect(x: 20, y: 4, width: 60, height: 24))
        prevButton.title = "⏮️"
        prevButton.bezelStyle = .rounded
        prevButton.target = self
        prevButton.action = #selector(previousImage)
        prevButton.isEnabled = status.imageCount > 0
        prevButton.toolTip = "Previous Image"

        // Start/Stop button (center)
        let startStopButton = NSButton(frame: NSRect(x: 90, y: 4, width: 100, height: 24))
        if status.isRunning {
            startStopButton.title = "⏹️ Stop"
            startStopButton.action = #selector(stopCycling)
        } else {
            startStopButton.title = "▶️ Start"
            startStopButton.action = #selector(startCycling)
        }
        startStopButton.bezelStyle = .rounded
        startStopButton.target = self
        startStopButton.isEnabled = status.canStartCycling || status.isRunning
        startStopButton.toolTip = status.isRunning ? "Stop Cycling" : "Start Cycling"

        // Next button
        let nextButton = NSButton(frame: NSRect(x: 200, y: 4, width: 60, height: 24))
        nextButton.title = "⏭️"
        nextButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(nextImage)
        nextButton.isEnabled = status.imageCount > 0
        nextButton.toolTip = "Next Image"

        // Add buttons to container
        containerView.addSubview(prevButton)
        containerView.addSubview(startStopButton)
        containerView.addSubview(nextButton)

        return containerView
    }

    private func addImageInfoSection(to menu: NSMenu, status: StatusInfo) {
        if let currentImage = status.currentImage {
            // Current image name (truncated if too long)
            let displayName = currentImage.count > 30 ? String(currentImage.prefix(27)) + "..." : currentImage
            let currentImageItem = NSMenuItem(title: "🎨 \(displayName)", action: nil, keyEquivalent: "")
            currentImageItem.isEnabled = false
            menu.addItem(currentImageItem)

            // Time until next change (only when running)
            if status.isRunning, let timeUntilNext = getTimeUntilNextChange() {
                let countdownItem = NSMenuItem(title: "⏰ Next in \(timeUntilNext)", action: nil, keyEquivalent: "")
                countdownItem.isEnabled = false
                menu.addItem(countdownItem)
            }
        } else {
            let noImageItem = NSMenuItem(title: "❌ No image selected", action: nil, keyEquivalent: "")
            noImageItem.isEnabled = false
            menu.addItem(noImageItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addQuickActionsSection(to menu: NSMenu, status: StatusInfo) {
        // Browse wallpapers
        let browseItem = NSMenuItem(title: "🖼️ Browse Wallpapers...", action: #selector(openWallpaperGallery), keyEquivalent: "")
        browseItem.target = self
        browseItem.isEnabled = status.imageCount > 0
        menu.addItem(browseItem)

        // Select folder
        let selectFolderItem = NSMenuItem(title: "📂 Select Folder...", action: #selector(selectFolder), keyEquivalent: "")
        selectFolderItem.target = self
        menu.addItem(selectFolderItem)

        // Rescan current folder
        if wallpaperViewModel?.selectedFolderPath != nil {
            let rescanItem = NSMenuItem(title: "🔄 Rescan Folder", action: #selector(rescanFolder), keyEquivalent: "")
            rescanItem.target = self
            rescanItem.isEnabled = !status.isScanning
            menu.addItem(rescanItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addPerformanceSection(to menu: NSMenu, status: StatusInfo) {
        // Performance info
        let memoryUsage = getMemoryUsage()
        let memoryItem = NSMenuItem(title: "💾 Memory: \(memoryUsage)", action: nil, keyEquivalent: "")
        memoryItem.isEnabled = false
        menu.addItem(memoryItem)

        if let avgChangeTime = getAverageChangeTime() {
            let perfItem = NSMenuItem(title: "⚡ Avg change: \(avgChangeTime)", action: nil, keyEquivalent: "")
            perfItem.isEnabled = false
            menu.addItem(perfItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addMainActionsSection(to menu: NSMenu) {
        // Open main window
        let openMainItem = NSMenuItem(title: "🏠 Open Wallpier", action: #selector(openMainWindow), keyEquivalent: "")
        openMainItem.target = self
        menu.addItem(openMainItem)

        // Settings
        let settingsItem = NSMenuItem(title: "⚙️ Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "❌ Quit Wallpier", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Helper Methods

    private func getTimeUntilNextChange() -> String? {
        guard let wallpaperVM = wallpaperViewModel,
              wallpaperVM.isRunning,
              wallpaperVM.timeUntilNextChange > 0 else { return nil }

        let remaining = Int(wallpaperVM.timeUntilNextChange)
        let minutes = remaining / 60
        let seconds = remaining % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func getMemoryUsage() -> String {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let result: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let memoryMB = Float(memoryInfo.resident_size) / 1024.0 / 1024.0
            return String(format: "%.1f MB", memoryMB)
        }
        return "Unknown"
    }

        private func getAverageChangeTime() -> String? {
        guard let wallpaperVM = wallpaperViewModel,
              wallpaperVM.averageWallpaperChangeTime > 0 else { return nil }

        return String(format: "%.2fs", wallpaperVM.averageWallpaperChangeTime)
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        isMenuVisible.toggle()
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @objc private func openMainWindow() {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    @objc private func openWallpaperGallery() {
        NotificationCenter.default.post(name: .openWallpaperGallery, object: nil)
    }

    @objc private func selectFolder() {
        NotificationCenter.default.post(name: .selectFolder, object: nil)
    }

    @objc private func rescanFolder() {
        wallpaperViewModel?.rescanCurrentFolder()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Wallpaper Controls

    @objc func startCycling() {
        Task {
            await wallpaperViewModel?.startCycling()
            // Force immediate menu update after starting
            DispatchQueue.main.async { [weak self] in
                self?.updateStatusItemAppearance()
                self?.updateMenu()
            }
        }
    }

    @objc func stopCycling() {
        wallpaperViewModel?.stopCycling()
        // Force immediate menu update after stopping
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItemAppearance()
            self?.updateMenu()
        }
    }

    @objc func nextImage() {
        wallpaperViewModel?.goToNextImage()
        // Update menu after navigation
        DispatchQueue.main.async { [weak self] in
            self?.updateMenu()
        }
    }

    @objc func previousImage() {
        wallpaperViewModel?.goToPreviousImage()
        // Update menu after navigation
        DispatchQueue.main.async { [weak self] in
            self?.updateMenu()
        }
    }

    // MARK: - Status Information

    struct StatusInfo {
        let isRunning: Bool
        let currentImage: String?
        let imageCount: Int
        let statusMessage: String
        let canStartCycling: Bool
        let isScanning: Bool
    }

    func getCurrentStatus() -> StatusInfo {
        guard let viewModel = wallpaperViewModel else {
            return StatusInfo(
                isRunning: false,
                currentImage: nil,
                imageCount: 0,
                statusMessage: "Not initialized",
                canStartCycling: false,
                isScanning: false
            )
        }

        return StatusInfo(
            isRunning: viewModel.isRunning,
            currentImage: viewModel.currentImage?.name,
            imageCount: viewModel.foundImages.count,
            statusMessage: viewModel.statusMessage,
            canStartCycling: viewModel.canStartCycling,
            isScanning: viewModel.isScanning
        )
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
    static let openWallpaperGallery = Notification.Name("openWallpaperGallery")
    static let selectFolder = Notification.Name("selectFolder")
    static let appWillTerminate = Notification.Name("appWillTerminate")
}

#Preview {
    StatusMenuView(
        wallpaperViewModel: WallpaperViewModel(),
        settingsViewModel: SettingsViewModel(settings: WallpaperSettings())
    )
}