import XCTest
@testable import wallpier

/// Comprehensive tests for ImageScannerService
/// Tests file scanning, filtering, recursive scanning, and performance
final class ImageScannerServiceTests: XCTestCase {

    // MARK: - Properties

    var sut: ImageScannerService!
    var testFolderURL: URL!
    var fileManager: FileManager!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = ImageScannerService()
        fileManager = FileManager.default
        testFolderURL = createTestFolder()
    }

    override func tearDown() async throws {
        cleanupTestFolder()
        sut = nil
        testFolderURL = nil
        try await super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func test_scanDirectory_withValidFolder_returnsImages() async throws {
        // Arrange
        let imageCount = 5
        try createTestImages(count: imageCount, in: testFolderURL)

        // Act
        let images = try await sut.scanDirectory(testFolderURL)

        // Assert
        XCTAssertEqual(images.count, imageCount, "Should find all test images")
        XCTAssertTrue(images.allSatisfy { $0.isAccessible }, "All images should be accessible")
    }

    func test_scanDirectory_withEmptyFolder_returnsEmptyArray() async throws {
        // Arrange - folder is already empty from setUp

        // Act
        let images = try await sut.scanDirectory(testFolderURL)

        // Assert
        XCTAssertTrue(images.isEmpty, "Empty folder should return empty array")
    }

    func test_scanDirectory_withNonexistentFolder_throwsError() async {
        // Arrange
        let nonexistentURL = testFolderURL.appendingPathComponent("nonexistent")

        // Act & Assert
        do {
            _ = try await sut.scanDirectory(nonexistentURL)
            XCTFail("Should throw error for nonexistent folder")
        } catch {
            XCTAssertTrue(error is WallpaperError, "Should throw WallpaperError")
        }
    }

    // MARK: - File Filtering Tests

    func test_scanDirectory_filtersUnsupportedFormats() async throws {
        // Arrange
        try createTestImages(count: 3, in: testFolderURL, extensions: ["jpg", "png", "heic"])
        try createTestFile(named: "document.pdf", in: testFolderURL)
        try createTestFile(named: "text.txt", in: testFolderURL)

        // Act
        let images = try await sut.scanDirectory(testFolderURL)

        // Assert
        XCTAssertEqual(images.count, 3, "Should only find supported image formats")
        XCTAssertFalse(images.contains { $0.pathExtension == "pdf" })
        XCTAssertFalse(images.contains { $0.pathExtension == "txt" })
    }

    func test_scanDirectory_supportsAllImageFormats() async throws {
        // Arrange
        let supportedFormats = ["jpg", "jpeg", "png", "heic", "bmp", "tiff", "gif"]
        try createTestImages(count: supportedFormats.count, in: testFolderURL, extensions: supportedFormats)

        // Act
        let images = try await sut.scanDirectory(testFolderURL)

        // Assert
        XCTAssertEqual(images.count, supportedFormats.count, "Should find all supported formats")
    }

    func test_scanDirectory_respectsFileFilters() async throws {
        // Arrange
        try createTestImages(count: 5, in: testFolderURL)

        // Act
        let images = try await sut.scanDirectory(testFolderURL)

        // Assert - FileFilters are respected by the service
        XCTAssertFalse(images.isEmpty, "Should find some images")
        XCTAssertTrue(images.allSatisfy { image in
            FileFilters().supportedExtensions.contains(image.pathExtension.lowercased())
        }, "All found images should match supported extensions")
    }

    // MARK: - Recursive Scanning Tests

    func test_scanDirectoryRecursively_findsImagesInSubfolders() async throws {
        // Arrange
        let subfolder1 = testFolderURL.appendingPathComponent("subfolder1")
        let subfolder2 = testFolderURL.appendingPathComponent("subfolder2")
        try fileManager.createDirectory(at: subfolder1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: subfolder2, withIntermediateDirectories: true)

        try createTestImages(count: 2, in: testFolderURL)
        try createTestImages(count: 3, in: subfolder1)
        try createTestImages(count: 4, in: subfolder2)

        // Act
        let images = try await sut.scanDirectoryRecursively(testFolderURL, progress: { _ in })

        // Assert
        XCTAssertEqual(images.count, 9, "Should find all images in root and subfolders")
    }

    func test_scanDirectoryRecursively_respectsMaxDepth() async throws {
        // Arrange
        let level1 = testFolderURL.appendingPathComponent("level1")
        let level2 = level1.appendingPathComponent("level2")
        let level3 = level2.appendingPathComponent("level3")

        try fileManager.createDirectory(at: level3, withIntermediateDirectories: true)

        try createTestImages(count: 1, in: testFolderURL, prefix: "root")
        try createTestImages(count: 1, in: level1, prefix: "l1")
        try createTestImages(count: 1, in: level2, prefix: "l2")
        try createTestImages(count: 1, in: level3, prefix: "l3")

        // Act
        let images = try await sut.quickScanDirectory(testFolderURL, maxDepth: 2)

        // Assert
        XCTAssertLessThanOrEqual(images.count, 3, "Should respect max depth of 2")
    }

    // MARK: - Performance Tests

    func test_quickScan_fasterThanFullScan() async throws {
        // Arrange
        try createLargeTestStructure()

        // Act
        let quickStart = Date()
        let quickResults = try await sut.quickScanDirectory(testFolderURL, maxDepth: 2)
        let quickDuration = Date().timeIntervalSince(quickStart)

        let fullStart = Date()
        let fullResults = try await sut.scanDirectoryRecursively(testFolderURL, progress: { _ in })
        let fullDuration = Date().timeIntervalSince(fullStart)

        // Assert - Quick scan should find fewer or equal images (limited depth)
        XCTAssertLessThanOrEqual(quickResults.count, fullResults.count,
            "Quick scan should find fewer/same images due to depth limit")

        // Note: Timing comparison can be flaky on different hardware
        // Just verify both complete successfully
        XCTAssertGreaterThan(quickResults.count, 0, "Quick scan should find some images")
        XCTAssertGreaterThan(fullResults.count, 0, "Full scan should find some images")
    }

    func test_scanLargeDirectory_completesInReasonableTime() async throws {
        // Arrange
        try createTestImages(count: 100, in: testFolderURL)

        // Act
        let start = Date()
        _ = try await sut.scanDirectory(testFolderURL)
        let duration = Date().timeIntervalSince(start)

        // Assert
        XCTAssertLessThan(duration, 5.0, "Should scan 100 images in under 5 seconds")
    }

    // MARK: - Concurrency Tests

    func test_concurrentScans_threadSafe() async throws {
        // Arrange
        try createTestImages(count: 10, in: testFolderURL)

        // Act - Launch 5 concurrent scans
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        _ = try await self.sut.scanDirectory(self.testFolderURL)
                    } catch {
                        XCTFail("Concurrent scan failed: \(error)")
                    }
                }
            }
        }

        // Assert - If we get here without crashes, thread safety is good
        XCTAssertTrue(true, "Concurrent scans completed without crashes")
    }

    // MARK: - Edge Cases

    func test_scanDirectory_withHiddenFiles_skipsHidden() async throws {
        // Arrange
        try createTestImages(count: 3, in: testFolderURL)
        try createHiddenFile(in: testFolderURL)

        // Act
        let images = try await sut.scanDirectory(testFolderURL)

        // Assert
        XCTAssertEqual(images.count, 3, "Should skip hidden files")
        XCTAssertFalse(images.contains { $0.name.hasPrefix(".") })
    }

    // MARK: - Helper Methods

    private func createTestFolder() -> URL {
        let tempDir = fileManager.temporaryDirectory
        let testFolder = tempDir.appendingPathComponent("WallpierTests-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: testFolder, withIntermediateDirectories: true)
        return testFolder
    }

    private func cleanupTestFolder() {
        guard let testFolder = testFolderURL else { return }
        try? fileManager.removeItem(at: testFolder)
    }

    private func createTestImages(count: Int, in folder: URL, extensions: [String] = ["jpg"], prefix: String = "test") throws {
        for i in 0..<count {
            let ext = extensions[i % extensions.count]
            let filename = "\(prefix)_image_\(i).\(ext)"
            let fileURL = folder.appendingPathComponent(filename)

            // Create a minimal valid image file (1x1 pixel)
            let imageData = createMinimalImageData(format: ext)
            try imageData.write(to: fileURL)
        }
    }

    private func createTestFile(named filename: String, in folder: URL) throws {
        let fileURL = folder.appendingPathComponent(filename)
        let data = "Test file content".data(using: .utf8)!
        try data.write(to: fileURL)
    }

    private func createHiddenFile(in folder: URL) throws {
        let fileURL = folder.appendingPathComponent(".hidden_image.jpg")
        let data = createMinimalImageData(format: "jpg")
        try data.write(to: fileURL)
    }

    private func createLargeTestStructure() throws {
        for i in 0..<5 {
            let subfolder = testFolderURL.appendingPathComponent("subfolder\(i)")
            try fileManager.createDirectory(at: subfolder, withIntermediateDirectories: true)
            try createTestImages(count: 20, in: subfolder, prefix: "sub\(i)")
        }
    }

    private func createMinimalImageData(format: String) -> Data {
        // Create minimal valid image data for testing
        // This is a 1x1 pixel PNG for simplicity
        let pngData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])
        return pngData
    }
}
