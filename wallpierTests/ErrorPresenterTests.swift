import XCTest
@testable import wallpier

/// Comprehensive tests for ErrorPresenter
/// Tests error presentation, conversion, auto-dismiss, and history management
@MainActor
final class ErrorPresenterTests: XCTestCase {

    // MARK: - Properties

    var sut: ErrorPresenter!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        sut = ErrorPresenter()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Error Presentation Tests

    func test_present_withError_setsCurrentError() {
        // Arrange
        let error = WallpaperError.fileNotFound

        // Act
        sut.present(error)

        // Assert
        XCTAssertNotNil(sut.currentError)
        XCTAssertTrue(sut.showError)
    }

    func test_present_withError_addsToHistory() {
        // Arrange
        let error1 = WallpaperError.fileNotFound
        let error2 = WallpaperError.folderNotFound

        // Act
        sut.present(error1)
        sut.present(error2)

        // Assert
        XCTAssertEqual(sut.errorHistory.count, 2)
    }

    func test_dismiss_clearsError() async {
        // Arrange
        sut.present(WallpaperError.fileNotFound)
        XCTAssertTrue(sut.showError)

        // Act
        sut.dismiss()

        // Assert
        XCTAssertFalse(sut.showError)

        // Wait for async cleanup
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(sut.currentError)
    }

    // MARK: - Error Conversion Tests

    func test_present_wallpaperError_convertsCorrectly() {
        // Arrange
        let error = WallpaperError.permissionDenied

        // Act
        sut.present(error, context: "Test Operation")

        // Assert
        guard let presentedError = sut.currentError else {
            XCTFail("Should have current error")
            return
        }

        XCTAssertEqual(presentedError.title, "Test Operation")
        XCTAssertNotNil(presentedError.message)
        XCTAssertNotNil(presentedError.recoverySuggestion)
        XCTAssertEqual(presentedError.severity, .error)
    }

    func test_present_scanError_convertsCorrectly() {
       // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/test")
        let error = ScanError.folderNotAccessible(testURL)

        // Act
        sut.present(error, context: "Scan Folder")

        // Assert
        guard let presentedError = sut.currentError else {
            XCTFail("Should have current error")
            return
        }

        XCTAssertEqual(presentedError.title, "Scan Folder")
        XCTAssertNotNil(presentedError.message)
        XCTAssertEqual(presentedError.severity, .error)
    }

    func test_present_cacheError_convertsCorrectly() {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/test.jpg")
        let error = CacheError.imageLoadFailed(testURL)

        // Act
        sut.present(error)

        // Assert
        guard let presentedError = sut.currentError else {
            XCTFail("Should have current error")
            return
        }

        XCTAssertNotNil(presentedError.message)
        // Note: Cache errors are presented as regular errors, not warnings
        // The severity is determined by ErrorPresenter's conversion logic
    }

    // MARK: - Error Code Tests

    func test_present_wallpaperError_hasCorrectCode() {
        // Arrange
        let testCases: [(WallpaperError, String)] = [
            (.permissionDenied, "W001"),
            (.invalidImageFormat, "W002"),
            (.folderNotFound, "W003"),
            (.systemIntegrationFailed, "W004"),
            (.fileNotFound, "W005"),
            (.unsupportedImageType, "W006"),
            (.noAvailableScreens, "W007")
        ]

        // Act & Assert
        for (error, expectedCode) in testCases {
            sut.present(error)
            XCTAssertEqual(sut.currentError?.errorCode, expectedCode, "Error code mismatch for \(error)")
        }
    }

    func test_present_scanError_hasCorrectCode() {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/test")
        let testCases: [(ScanError, String)] = [
            (.folderNotAccessible(testURL), "S001"),
            (.noImagesFound(testURL), "S002"),
            (.cancelled, "S003")
        ]

        // Act & Assert
        for (error, expectedCode) in testCases {
            sut.present(error)
            XCTAssertEqual(sut.currentError?.errorCode, expectedCode, "Error code mismatch for \(error)")
        }
    }

    // MARK: - Auto-Dismiss Tests

    func test_present_withWarning_autoDismisses() async {
        // Arrange
        sut.presentWarning("Test warning")
        XCTAssertTrue(sut.showError)

        // Act - Wait for auto-dismiss (5 seconds + buffer)
        try? await Task.sleep(nanoseconds: 5_500_000_000)

        // Assert
        XCTAssertFalse(sut.showError, "Warning should auto-dismiss")
    }

    func test_present_withInfo_autoDismisses() async {
        // Arrange
        sut.presentInfo("Test info")
        XCTAssertTrue(sut.showError)

        // Act - Wait for auto-dismiss
        try? await Task.sleep(nanoseconds: 5_500_000_000)

        // Assert
        XCTAssertFalse(sut.showError, "Info should auto-dismiss")
    }

    func test_present_withError_doesNotAutoDismiss() async {
        // Arrange
        sut.present(WallpaperError.fileNotFound)
        XCTAssertTrue(sut.showError)

        // Act - Wait equivalent to auto-dismiss time
        try? await Task.sleep(nanoseconds: 5_500_000_000)

        // Assert
        XCTAssertTrue(sut.showError, "Error should not auto-dismiss")
    }

    // MARK: - History Management Tests

    func test_errorHistory_limitsToMaxCount() {
        // Arrange & Act - Present more than max (50) errors
        for i in 0..<60 {
            sut.present(WallpaperError.fileNotFound, context: "Error \(i)")
        }

        // Assert
        XCTAssertLessThanOrEqual(sut.errorHistory.count, 50, "Should limit history to 50 entries")
    }

    func test_clearHistory_removesAllErrors() {
        // Arrange
        sut.present(WallpaperError.fileNotFound)
        sut.present(WallpaperError.folderNotFound)
        XCTAssertFalse(sut.errorHistory.isEmpty)

        // Act
        sut.clearHistory()

        // Assert
        XCTAssertTrue(sut.errorHistory.isEmpty)
    }

    // MARK: - Convenience Method Tests

    func test_presentWarning_createsPresentedError() {
        // Act
        sut.presentWarning("Test message", title: "Test Warning")

        // Assert
        guard let error = sut.currentError else {
            XCTFail("Should have current error")
            return
        }

        XCTAssertEqual(error.title, "Test Warning")
        XCTAssertEqual(error.message, "Test message")
        XCTAssertEqual(error.severity, .warning)
    }

    func test_presentInfo_createsPresentedError() {
        // Act
        sut.presentInfo("Test message", title: "Test Info")

        // Assert
        guard let error = sut.currentError else {
            XCTFail("Should have current error")
            return
        }

        XCTAssertEqual(error.title, "Test Info")
        XCTAssertEqual(error.message, "Test message")
        XCTAssertEqual(error.severity, .info)
    }
}
