//
//  wallpierApp.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Notification Names
extension Notification.Name {
    static let openMainWindow = Notification.Name("com.oxystack.wallpier.openMainWindow")
    static let openSettings = Notification.Name("com.oxystack.wallpier.openSettings")
    static let openWallpaperGallery = Notification.Name("com.oxystack.wallpier.openWallpaperGallery")
    static let selectFolder = Notification.Name("com.oxystack.wallpier.selectFolder")
    static let appWillTerminate = Notification.Name("com.oxystack.wallpier.appWillTerminate")
}

@main
struct WallpierApp: App {
    // MARK: - State Objects

    @StateObject private var wallpaperViewModel = WallpaperViewModel()
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var errorPresenter = ErrorPresenter()
    @StateObject private var systemService = SystemService()
    @State private var showingSettings = false

    // MARK: - App Storage

    @AppStorage("hideDock") private var hideDock = false
    @AppStorage("showsMenuBar") private var showsMenuBar = true
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    init() {
        // Load settings for SettingsViewModel
        let settings = WallpaperSettings.load()
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(settings: settings))

        AppIntentsMetadataController.apply(disableExtraction: settings.advancedSettings.disableAppIntentsMetadataExtraction)

        // Setup app delegate
        NSApplication.shared.delegate = AppDelegate.shared
    }

    /// Get the current accent color from settings
    private var appAccentColor: Color {
        settingsViewModel.settings.advancedSettings.accentColor
    }

    @SceneBuilder
    var body: some Scene {
        // Main Window
        WindowGroup("Wallpier", id: "mainWindow") {
            ContentView()
                .environmentObject(wallpaperViewModel)
                .environmentObject(settingsViewModel)
                .environmentObject(systemService)
                .environmentObject(errorPresenter)
                .tint(appAccentColor)
                .frame(minWidth: 950, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                    // Bring app to front
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    showingSettings = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .openWallpaperGallery)) { _ in
                    // Open wallpaper gallery - trigger the browse button action
                    if NSApp.mainWindow?.contentView != nil {
                        NotificationCenter.default.post(name: Notification.Name("TriggerWallpaperGallery"), object: nil)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .selectFolder)) { _ in
                    // Trigger folder selection
                    settingsViewModel.selectFolder()
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(viewModel: settingsViewModel)
                        .environmentObject(systemService)
                        .tint(appAccentColor)
                }
                .onAppear {
                    // Ensure WallpaperViewModel has the correct settings from app startup
                    wallpaperViewModel.updateSettings(settingsViewModel.settings)

                    // Initial system setup
                    Task {
                        // Only request permissions if this is first launch and no folder is selected
                        if isFirstLaunch() && settingsViewModel.settings.folderPath == nil {
                            let _ = await systemService.requestPermissions()
                        }
                        await setupInitialAppBehavior()
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            // Custom menu commands
            CommandGroup(replacing: .newItem) {
                Button("Select Folder...") {
                    settingsViewModel.selectFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .windowArrangement) {
                Button("Start Cycling") {
                    Task { await wallpaperViewModel.startCycling() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(wallpaperViewModel.isRunning || !wallpaperViewModel.canStartCycling)

                Button("Stop Cycling") {
                    wallpaperViewModel.stopCycling()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!wallpaperViewModel.isRunning)

                Divider()

                Button("Next Image") {
                    wallpaperViewModel.goToNextImage()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!wallpaperViewModel.canAdvance)

                Button("Previous Image") {
                    wallpaperViewModel.goToPreviousImage()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!wallpaperViewModel.canGoBack)
            }
        }
        // Menu Bar Extra - conditionally inserted via isInserted to avoid SceneBuilder ambiguity
        MenuBarExtra(
            "Wallpier",
            systemImage: "photo.on.rectangle.angled",
            isInserted: .constant(settingsViewModel.settings.showMenuBarIcon)
        ) {
            StatusMenuContent(
                wallpaperViewModel: wallpaperViewModel,
                settingsViewModel: settingsViewModel,
                systemService: systemService
            )
            .id("\(wallpaperViewModel.isRunning)_\(UUID())")
        }
        .menuBarExtraStyle(.menu)
    }

    // MARK: - Initial Setup

    private func setupInitialAppBehavior() async {
        // Configure dock visibility based on settings
        let hideDock = settingsViewModel.settings.systemIntegration.hideDockIcon
        systemService.configureDockVisibility(!hideDock)

        // Show initial setup dialogs only if this is first launch and no folder selected
        if isFirstLaunch() && settingsViewModel.settings.folderPath == nil {
            await showFirstLaunchSetup()
        }
    }

    private func isFirstLaunch() -> Bool {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            return true
        }
        return false
    }

    private func showFirstLaunchSetup() async {
        // Show welcome and setup dialogs
        // Delay to allow UI to settle
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        if self.systemService.showPermissionRequestDialog() {
            // User wants to continue with setup
            if let enableStartup = self.systemService.showLaunchAtStartupDialog() {
                let _ = await self.systemService.setLaunchAtStartup(enableStartup)
            }
        }
    }
}

// MARK: - Menu Bar Content

struct StatusMenuContent: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var systemService: SystemService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if settingsViewModel.settings.showMenuBarIcon {
            // Full menu content when enabled
            // Status Section
            HStack {
                Circle()
                    .fill(wallpaperViewModel.isRunning ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(wallpaperViewModel.isRunning ? "Running" : "Stopped")
                    .font(.subheadline)
            }

            Text("\(wallpaperViewModel.foundImages.count) images found")
                .font(.caption)
                .foregroundColor(.secondary)

            if let currentImage = wallpaperViewModel.currentImage {
                Text("Current: \(currentImage.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

                        Divider()

                        // Quick Controls - custom horizontal layout that works in menu bar
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button(action: { wallpaperViewModel.goToPreviousImage() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "backward.fill")
                                .frame(width: 12, height: 12)
                            Text("Previous")
                                .font(.caption)
                        }
                    }
                    .disabled(!wallpaperViewModel.canGoBack)
                    .buttonStyle(.borderless)
                    .help("Previous image")

                    Button(action: toggleCycling) {
                        HStack(spacing: 4) {
                            Image(systemName: wallpaperViewModel.isRunning ? "stop.fill" : "play.fill")
                                .frame(width: 12, height: 12)
                            Text(wallpaperViewModel.isRunning ? "Stop" : "Start")
                                .font(.caption)
                        }
                    }
                    .disabled(wallpaperViewModel.isRunning ? false : !wallpaperViewModel.canStartCycling)
                    .buttonStyle(.borderless)
                    .help(wallpaperViewModel.isRunning ? "Stop cycling" : "Start cycling")

                    Button(action: { wallpaperViewModel.goToNextImage() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                                .frame(width: 12, height: 12)
                            Text("Next")
                                .font(.caption)
                        }
                    }
                    .disabled(!wallpaperViewModel.canAdvance)
                    .buttonStyle(.borderless)
                    .help("Next image")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }

            Divider()

            // Menu Items
            Button("Open Wallpier") {
                openMainWindow()
            }

            Button("Settings...") {
                openSettings()
            }

            Divider()

            Button("Quit Wallpier") {
                NSApplication.shared.terminate(nil)
            }
        } else {
            // Minimal menu when disabled - just essential functions
            Text("Menu Bar Icon Disabled")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Button("Open Wallpier") {
                openMainWindow()
            }

            Button("Settings...") {
                openSettings()
            }

            Divider()

            Button("Quit Wallpier") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func toggleCycling() {
        if wallpaperViewModel.isRunning {
            wallpaperViewModel.stopCycling()
        } else {
            Task { await wallpaperViewModel.startCycling() }
        }
    }

    private func openMainWindow() {
        openWindow(id: "mainWindow")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        openWindow(id: "mainWindow")
        NotificationCenter.default.post(name: .openSettings, object: nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

// MARK: - App Delegate for Additional Setup

class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup any additional app-wide configurations
        setupAppearance()
        setupSystemBehavior()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when all windows are closed (menu bar app behavior)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When clicking dock icon (if visible), show main window
        if !flag {
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Perform cleanup before termination
        NotificationCenter.default.post(name: .appWillTerminate, object: nil);
    }

    private func setupAppearance() {
        // Configure app-wide appearance if needed
        if #available(macOS 14.0, *) {
            // Modern macOS appearance configurations
        }
    }

    private func setupSystemBehavior() {
        // Additional system-level setup
        NSApp.setActivationPolicy(.regular)
    }
}

// MARK: - View Extensions

extension View {
    /// Applies consistent styling for the wallpaper app
    func wallpierStyle() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
    }
}
