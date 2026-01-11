import XCTest
@testable import wallpier

/// Comprehensive tests for RetryUtility
/// Tests retry logic, exponential backoff, and error classification
final class RetryUtilityTests: XCTestCase {

    // MARK: - Basic Retry Logic Tests

    func test_withRetry_succeedsOnFirstAttempt() async throws {
        // Arrange
        var attemptCount = 0

        // Act
        let result = try await RetryUtility.withRetry {
            attemptCount += 1
            return "success"
        }

        // Assert
        XCTAssertEqual(result, "success")
        XCTAssertEqual(attemptCount, 1, "Should succeed on first attempt")
    }

    func test_withRetry_retriesOnFailure() async throws {
        // Arrange
        var attemptCount = 0

        // Act
        let result = try await RetryUtility.withRetry(maxAttempts: 3, baseDelay: 0.1) {
            attemptCount += 1
            if attemptCount < 3 {
                throw NSError(domain: "test", code: 1)
            }
            return "success"
        }

        // Assert
        XCTAssertEqual(result, "success")
        XCTAssertEqual(attemptCount, 3, "Should retry until success")
    }

func test_withRetry_respectsMaxAttempts() async throws {
        // Arrange
        var attemptCount = 0

        // Act & Assert
        do {
            _ = try await RetryUtility.withRetry(maxAttempts: 3, baseDelay: 0.1) {
                attemptCount += 1
                throw NSError(domain: "test", code: 1)
            }
            XCTFail("Should throw after max attempts")
        } catch {
            XCTAssertEqual(attemptCount, 3, "Should attempt exactly 3 times")
        }
    }

    func test_withRetry_exponentialBackoff() async throws {
        // Arrange
        var attemptTimes: [Date] = []
        let baseDelay: TimeInterval = 0.5

        // Act
        do {
            _ = try await RetryUtility.withRetry(maxAttempts: 3, baseDelay: baseDelay) {
                attemptTimes.append(Date())
                throw NSError(domain: "test", code: 1)
            }
        } catch {
            // Expected to fail
        }

        // Assert - Check delays are approximately exponential
        XCTAssertEqual(attemptTimes.count, 3)
        if attemptTimes.count == 3 {
            let delay1 = attemptTimes[1].timeIntervalSince(attemptTimes[0])
            let delay2 = attemptTimes[2].timeIntervalSince(attemptTimes[1])

            // First delay should be ~baseDelay * 1 = 0.5s
            XCTAssertGreaterThanOrEqual(delay1, baseDelay * 0.9)
            XCTAssertLessThanOrEqual(delay1, baseDelay * 1.5)

            // Second delay should be ~baseDelay * 2 = 1.0s
            XCTAssertGreaterThanOrEqual(delay2, baseDelay * 1.8)
            XCTAssertLessThanOrEqual(delay2, baseDelay * 2.5)
        }
    }

    // MARK: - Error Classification Tests

    func test_isRetryableError_returnsTrueForTransient() {
        // Arrange
        let transientErrors: [Error] = [
            WallpaperError.systemIntegrationFailed,
            WallpaperError.setWallpaperFailed(underlying: NSError(domain: "test", code: 1)),
            CacheError.imageLoadFailed(URL(fileURLWithPath: "/tmp/test.jpg"))
        ]

        // Act & Assert
        for error in transientErrors {
            XCTAssertTrue(
                RetryUtility.isRetryableError(error),
                "\(error) should be retryable"
            )
        }
    }

    func test_isRetryableError_returnsFalseForPermanent() {
        // Arrange
        let permanentErrors: [Error] = [
            WallpaperError.fileNotFound,
            WallpaperError.folderNotFound,
            WallpaperError.permissionDenied,
            ScanError.folderNotAccessible(URL(fileURLWithPath: "/tmp")),
            ScanError.cancelled
        ]

        // Act & Assert
        for error in permanentErrors {
            XCTAssertFalse(
                RetryUtility.isRetryableError(error),
                "\(error) should not be retryable"
            )
        }
    }

    // MARK: - Conditional Retry Tests

    func test_withRetry_doesNotRetryNonRetryableErrors() async throws {
        // Arrange
        var attemptCount = 0

        // Act &Assert
        do {
            _ = try await RetryUtility.withRetry(
                maxAttempts: 3,
                baseDelay: 0.1,
                shouldRetry: RetryUtility.isRetryableError
            ) {
                attemptCount += 1
                throw WallpaperError.fileNotFound
            }
            XCTFail("Should throw immediately")
        } catch {
            XCTAssertEqual(attemptCount, 1, "Should not retry non-retryable error")
        }
    }

    func test_withRetry_retriesRetryableErrors() async throws {
        // Arrange
        var attemptCount = 0

        // Act & Assert
        do {
            _ = try await RetryUtility.withRetry(
                maxAttempts: 3,
                baseDelay: 0.1,
                shouldRetry: RetryUtility.isRetryableError
            ) {
                attemptCount += 1
                throw WallpaperError.systemIntegrationFailed
            }
        } catch {
            XCTAssertEqual(attemptCount, 3, "Should retry retryable error")
        }
    }

    // MARK: - Edge Cases

    func test_withRetry_withMaxAttempts1_noRetry() async throws {
        // Arrange
        var attemptCount = 0

        // Act & Assert
        do {
            _ = try await RetryUtility.withRetry(maxAttempts: 1, baseDelay: 0.1) {
                attemptCount += 1
                throw NSError(domain: "test", code: 1)
            }
        } catch {
            XCTAssertEqual(attemptCount, 1, "Should not retry with maxAttempts=1")
        }
    }

    func test_withRetry_throwsOriginalError() async throws {
        // Arrange
        let originalError = NSError(domain: "test.domain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        // Act & Assert
        do {
            _ = try await RetryUtility.withRetry(maxAttempts: 2, baseDelay: 0.1) {
                throw originalError
            }
            XCTFail("Should throw error")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, originalError.domain)
            XCTAssertEqual(error.code, originalError.code)
        }
    }
}
