//
//  wallpierTests.swift
//  wallpierTests
//
//  Created by Yuuta on 28.06.2025.
//

import Testing
import Foundation
@testable import wallpier

// MARK: - WallpaperSettings Tests

struct WallpaperSettingsTests {

    @Test func testDefaultInitialization() async throws {
        let settings = WallpaperSettings()

        #expect(settings.version == WallpaperSettings.currentVersion)
        #expect(settings.folderPath == nil)
        #expect(settings.isRecursiveScanEnabled == true)
        #expect(settings.cyclingInterval == 300) // 5 minutes default
        #expect(settings.isCyclingEnabled == false)
        #expect(settings.scalingMode == .fill)
        #expect(settings.sortOrder == .random)
        #expect(settings.isShuffleEnabled == true)
        #expect(settings.showMenuBarIcon == true)
    }

    @Test func testCyclingIntervalValidation() async throws {
        var settings = WallpaperSettings()

        // Valid interval
        settings.cyclingInterval = 60
        let validErrors = settings.validate()
        #expect(!validErrors.contains { $0.contains("interval") })

        // Too short
        settings.cyclingInterval = 5
        let shortErrors = settings.validate()
        #expect(shortErrors.contains { $0.contains("at least 10 seconds") })

        // Too long
        settings.cyclingInterval = 100000
        let longErrors = settings.validate()
        #expect(longErrors.contains { $0.contains("cannot exceed 24 hours") })
    }

    @Test func testCyclingIntervalDescription() async throws {
        var settings = WallpaperSettings()

        // Seconds
        settings.cyclingInterval = 30
        #expect(settings.cyclingIntervalDescription == "30 seconds")

        // Minutes
        settings.cyclingInterval = 60
        #expect(settings.cyclingIntervalDescription == "1 minute")

        settings.cyclingInterval = 300
        #expect(settings.cyclingIntervalDescription == "5 minutes")

        // Hours
        settings.cyclingInterval = 3600
        #expect(settings.cyclingIntervalDescription == "1 hour")

        settings.cyclingInterval = 7200
        #expect(settings.cyclingIntervalDescription == "2 hours")

        // Hours + minutes
        settings.cyclingInterval = 3900 // 1h 5m
        #expect(settings.cyclingIntervalDescription == "1h 5m")
    }
}

// MARK: - ImageFile Tests

struct ImageFileTests {

    @Test func testImageFileCreation() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/test_image.jpg")
        let imageFile = ImageFile(
            url: testURL,
            name: "test_image.jpg",
            size: 1024,
            modificationDate: Date(),
            pathExtension: "jpg"
        )

        #expect(imageFile.name == "test_image.jpg")
        #expect(imageFile.size == 1024)
        #expect(imageFile.pathExtension == "jpg")
        #expect(imageFile.url == testURL)
    }

    @Test func testImageFileHashable() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.jpg")
        let now = Date()

        let file1 = ImageFile(url: testURL, name: "test.jpg", size: 1024, modificationDate: now, pathExtension: "jpg")
        let file2 = ImageFile(url: testURL, name: "test.jpg", size: 1024, modificationDate: now, pathExtension: "jpg")

        // Each ImageFile has a unique UUID so they should not be equal
        #expect(file1.id != file2.id)
    }

    @Test func testFormattedSize() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.jpg")

        // Test various sizes
        let small = ImageFile(url: testURL, name: "small.jpg", size: 512, modificationDate: Date(), pathExtension: "jpg")
        #expect(small.formattedSize.contains("512") || small.formattedSize.contains("bytes"))

        let medium = ImageFile(url: testURL, name: "medium.jpg", size: 1024 * 1024, modificationDate: Date(), pathExtension: "jpg")
        #expect(medium.formattedSize.contains("MB") || medium.formattedSize.contains("1"))
    }
}

// MARK: - CycleConfiguration Tests

struct CycleConfigurationTests {

    @Test func testDefaultInitialization() async throws {
        let config = CycleConfiguration()

        #expect(config.imageQueue.isEmpty)
        #expect(config.currentIndex == 0)
        #expect(config.isActive == false)
        #expect(config.history.isEmpty)
    }

    @Test func testQueueOperations() async throws {
        var config = CycleConfiguration()
        let testURL = URL(fileURLWithPath: "/tmp/test.jpg")

        let images = (0..<5).map { i in
            ImageFile(url: testURL.appendingPathComponent("\(i).jpg"), name: "\(i).jpg", size: 1024, modificationDate: Date(), pathExtension: "jpg")
        }

        config.updateQueue(images)
        #expect(config.imageQueue.count == 5)
        #expect(config.currentImage != nil)
    }

    @Test func testAdvanceToNext() async throws {
        var config = CycleConfiguration()
        let testURL = URL(fileURLWithPath: "/tmp/test.jpg")

        let images = (0..<3).map { i in
            ImageFile(url: testURL.appendingPathComponent("\(i).jpg"), name: "\(i).jpg", size: 1024, modificationDate: Date(), pathExtension: "jpg")
        }

        config.updateQueue(images)
        #expect(config.currentIndex == 0)

        let next = config.advanceToNext()
        #expect(next != nil)
        #expect(config.currentIndex == 1)

        let next2 = config.advanceToNext()
        #expect(next2 != nil)
        #expect(config.currentIndex == 2)

        // Should wrap around
        let next3 = config.advanceToNext()
        #expect(next3 != nil)
        #expect(config.currentIndex == 0)
    }

    @Test func testGoBack() async throws {
        var config = CycleConfiguration()
        let testURL = URL(fileURLWithPath: "/tmp/test.jpg")

        let images = (0..<3).map { i in
            ImageFile(url: testURL.appendingPathComponent("\(i).jpg"), name: "\(i).jpg", size: 1024, modificationDate: Date(), pathExtension: "jpg")
        }

        config.updateQueue(images)
        _ = config.advanceToNext() // Now at index 1
        _ = config.advanceToNext() // Now at index 2
        #expect(config.currentIndex == 2)

        // Use jumpToImage to go to previous position
        let prev = config.jumpToImage(at: 1)
        #expect(prev != nil)
        #expect(config.currentIndex == 1)
    }

    @Test func testShuffleQueue() async throws {
        var config = CycleConfiguration()
        let testURL = URL(fileURLWithPath: "/tmp/test.jpg")

        let images = (0..<10).map { i in
            ImageFile(url: testURL.appendingPathComponent("\(i).jpg"), name: "\(i).jpg", size: 1024, modificationDate: Date(), pathExtension: "jpg")
        }

        config.updateQueue(images)
        let originalOrder = config.imageQueue.map { $0.name }

        config.shuffleQueue()
        let shuffledOrder = config.imageQueue.map { $0.name }

        // After shuffle, order should likely be different (very low probability of same order)
        // Just check that we still have all images
        #expect(config.imageQueue.count == 10)
        #expect(Set(shuffledOrder) == Set(originalOrder))
    }
}

// MARK: - ScreenID Tests

struct ScreenIDTests {

    @Test func testScreenIDEquality() async throws {
        let id1 = ScreenID(rawValue: "Display-0x0-1920x1080")
        let id2 = ScreenID(rawValue: "Display-0x0-1920x1080")
        let id3 = ScreenID(rawValue: "External-1920x0-1920x1080")

        #expect(id1 == id2)
        #expect(id1 != id3)
    }

    @Test func testScreenIDHashable() async throws {
        let id1 = ScreenID(rawValue: "Display-0x0-1920x1080")
        let id2 = ScreenID(rawValue: "Display-0x0-1920x1080")

        var dict = [ScreenID: String]()
        dict[id1] = "Main"
        dict[id2] = "Updated"

        // Same key should overwrite
        #expect(dict.count == 1)
        #expect(dict[id1] == "Updated")
    }
}

// MARK: - ScreenCycleController Tests

struct ScreenCycleControllerTests {

    @Test func testClear() async throws {
        var controller = ScreenCycleController()

        #expect(controller.isEmpty)

        // Simulate adding some data indirectly through the controller
        // Since we can't directly set indices, we test the isEmpty state
        controller.clear()
        #expect(controller.isEmpty)
    }
}

// MARK: - Scaling Mode Tests

struct ScalingModeTests {

    @Test func testDisplayNames() async throws {
        #expect(WallpaperScalingMode.fill.displayName == "Fill Screen")
        #expect(WallpaperScalingMode.fit.displayName == "Fit to Screen")
        #expect(WallpaperScalingMode.stretch.displayName == "Stretch to Fill")
        #expect(WallpaperScalingMode.center.displayName == "Center")
        #expect(WallpaperScalingMode.tile.displayName == "Tile")
    }

    @Test func testAllCases() async throws {
        #expect(WallpaperScalingMode.allCases.count == 5)
    }
}

// MARK: - FileFilters Tests

struct FileFiltersTests {

    @Test func testDefaultExtensions() async throws {
        let filters = FileFilters()

        let extensions = filters.supportedExtensions

        // Default always includes these
        #expect(extensions.contains("jpg"))
        #expect(extensions.contains("jpeg"))
        #expect(extensions.contains("png"))
        #expect(extensions.contains("bmp"))
        #expect(extensions.contains("tiff"))

        // Default includes HEIC, GIF, WebP
        #expect(extensions.contains("heic"))
        #expect(extensions.contains("gif"))
        #expect(extensions.contains("webp"))
    }

    @Test func testFilteredExtensions() async throws {
        var filters = FileFilters()
        filters.includeHEICFiles = false
        filters.includeGIFFiles = false
        filters.includeWebPFiles = false

        let extensions = filters.supportedExtensions

        #expect(!extensions.contains("heic"))
        #expect(!extensions.contains("gif"))
        #expect(!extensions.contains("webp"))

        // Base types still included
        #expect(extensions.contains("jpg"))
        #expect(extensions.contains("png"))
    }
}

// MARK: - Error Tests

struct ErrorTests {

    @Test func testWallpaperErrorDescriptions() async throws {
        let errors: [WallpaperError] = [
            .permissionDenied,
            .invalidImageFormat,
            .folderNotFound,
            .fileNotFound,
            .unsupportedImageType,
            .noAvailableScreens,
            .systemIntegrationFailed
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        }
    }

    @Test func testScanErrorDescriptions() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/test")
        let errors: [ScanError] = [
            .folderNotAccessible(testURL),
            .noImagesFound(testURL),
            .cancelled
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion != nil)
        }
    }
}
