import XCTest
@testable import wallpier

@MainActor
final class ImageCacheServiceTests: XCTestCase {

    func testUpdateConfigurationClampsAndResizesUpperBounds() {
        let service = ImageCacheService(maxCacheSizeMB: 25, enableLogging: false)

        let initialSize = service.getCacheSize()
        XCTAssertEqual(initialSize, expectedCacheSize(for: 25))

        service.updateConfiguration(maxCacheSizeMB: 50, enableLogging: false)
        XCTAssertEqual(service.getCacheSize(), expectedCacheSize(for: 50))

        // Clamps to 100MB when configured above the limit
        service.updateConfiguration(maxCacheSizeMB: 200, enableLogging: false)
        XCTAssertEqual(service.getCacheSize(), expectedCacheSize(for: 100))

        // No-op when configuration is unchanged
        service.updateConfiguration(maxCacheSizeMB: 100, enableLogging: false)
        XCTAssertEqual(service.getCacheSize(), expectedCacheSize(for: 100))
    }

    func testUpdateConfigurationClampsLowerBound() {
        let service = ImageCacheService(maxCacheSizeMB: 25, enableLogging: false)

        service.updateConfiguration(maxCacheSizeMB: 1, enableLogging: false)
        XCTAssertEqual(service.getCacheSize(), expectedCacheSize(for: 5))

        // Re-applying the same values should not change limits
        service.updateConfiguration(maxCacheSizeMB: 1, enableLogging: false)
        XCTAssertEqual(service.getCacheSize(), expectedCacheSize(for: 5))
    }

    // MARK: - Helpers

    private func expectedCacheSize(for sizeMB: Int) -> Int {
        let clamped = max(5, min(sizeMB, 100))
        let bytes = clamped * 1_024 * 1_024

        let mainLimit = Int(Double(bytes) * 0.6)
        let thumbLimit = Int(Double(bytes) * 0.3)

        let estimatedMain = min(mainLimit, clamped * 1_024 * 1_024 * 7 / 10)
        let estimatedThumb = min(thumbLimit, clamped * 1_024 * 1_024 * 2 / 10)

        return estimatedMain + estimatedThumb
    }
}
