import XCTest
@testable import wallpier

@MainActor
final class SettingsMigrationTests: XCTestCase {
    private var previousData: Data?
    private let defaults = UserDefaults.standard
    private let key = "WallpaperSettings"

    override func setUp() {
        super.setUp()
        previousData = defaults.data(forKey: key)
        defaults.removeObject(forKey: key)
    }

    override func tearDown() {
        if let previousData {
            defaults.set(previousData, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testLoadMigratesVersionAndPreservesAdvancedSettings() throws {
        var legacy = WallpaperSettings()
        legacy.version = WallpaperSettings.currentVersion - 1
        legacy.advancedSettings.maxCacheSizeMB = 250

        let encoded = try JSONEncoder().encode(legacy)
        defaults.set(encoded, forKey: key)

        let loaded = WallpaperSettings.load()

        XCTAssertEqual(loaded.version, WallpaperSettings.currentVersion)
        XCTAssertEqual(loaded.advancedSettings.maxCacheSizeMB, 250)
    }

    func testLoadClampsInvalidAdvancedSettings() throws {
        var invalid = WallpaperSettings()
        invalid.version = 0
        invalid.advancedSettings.maxCacheSizeMB = 2000

        let encoded = try JSONEncoder().encode(invalid)
        defaults.set(encoded, forKey: key)

        let loaded = WallpaperSettings.load()

        XCTAssertEqual(loaded.advancedSettings.maxCacheSizeMB, 100)
    }

    func testSaveAndLoadAdvancedSettingsThroughViewModel() {
        var settings = WallpaperSettings()
        settings.advancedSettings.maxCacheSizeMB = 250

        let viewModel = SettingsViewModel(settings: settings)
        viewModel.saveSettings()

        let reloaded = WallpaperSettings.load()
        XCTAssertEqual(reloaded.advancedSettings.maxCacheSizeMB, 250)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
}
