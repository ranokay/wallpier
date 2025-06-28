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
struct wallpierApp: App {
    @StateObject private var wallpaperViewModel = WallpaperViewModel()
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var systemService = SystemService()
    @State private var showingMainWindow = true
    @State private var showingSettings = false

    init() {
        let settings = WallpaperSettings.load()
        self._settingsViewModel = StateObject(wrappedValue: SettingsViewModel(settings: settings))

        // Setup app delegate
        NSApplication.shared.delegate = AppDelegate.shared
    }

    var body: some Scene {
        // Main Window
        WindowGroup("Wallpier") {
            ContentView()
                .environmentObject(wallpaperViewModel)
                .environmentObject(settingsViewModel)
                .environmentObject(systemService)
                .frame(minWidth: 800, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                    showingMainWindow = true
                    // Bring app to front
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    showingSettings = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .openWallpaperGallery)) { _ in
                    // Open wallpaper gallery - trigger the browse button action
                    if let window = NSApp.mainWindow?.contentView {
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
                }
                .onAppear {
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

        // Settings Window (separate window group)
        WindowGroup("Wallpier Settings", id: "settings") {
            SettingsView(viewModel: settingsViewModel)
                .environmentObject(systemService)
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Menu Bar Extra with fixes for state and layout
        MenuBarExtra("Wallpier", systemImage: "photo.on.rectangle.angled") {
            // Use an ID to force the menu to update when state changes
            StatusMenuContent(
                wallpaperViewModel: wallpaperViewModel,
                settingsViewModel: settingsViewModel,
                systemService: systemService
            )
            .id(wallpaperViewModel.isRunning)
        }
        .menuBarExtraStyle(.menu)
    }

    // MARK: - Initial Setup

    private func setupInitialAppBehavior() async {
        // Configure dock visibility based on settings
        let hideDock = settingsViewModel.settings.systemIntegration?.hideDockIcon ?? false
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

    var body: some View {
        // App Title Section (as a disabled menu item)
        HStack {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundColor(.accentColor)
            Text("Wallpier")
                .font(.headline)
        }

        Divider()

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

        // Quick Controls in a single horizontal row
        HStack(spacing: 24) {
            Button(action: { wallpaperViewModel.goToPreviousImage() }) {
                Image(systemName: "backward.fill")
                    .help("Previous image")
            }
            .disabled(!wallpaperViewModel.canGoBack)

            Button(action: toggleCycling) {
                Image(systemName: wallpaperViewModel.isRunning ? "stop.fill" : "play.fill")
                    .help(wallpaperViewModel.isRunning ? "Stop cycling" : "Start cycling")
            }
            .disabled(wallpaperViewModel.isRunning ? false : !wallpaperViewModel.canStartCycling)

            Button(action: { wallpaperViewModel.goToNextImage() }) {
                Image(systemName: "forward.fill")
                    .help("Next image")
            }
            .disabled(!wallpaperViewModel.canAdvance)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)

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
    }

    private func toggleCycling() {
        if wallpaperViewModel.isRunning {
            wallpaperViewModel.stopCycling()
        } else {
            Task { await wallpaperViewModel.startCycling() }
        }
    }

    private func openMainWindow() {
        // Open or focus main window
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Wallpier" }) {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            // Create new window if needed
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
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
