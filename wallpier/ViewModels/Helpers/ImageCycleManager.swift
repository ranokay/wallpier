//
//  ImageCycleManager.swift
//  wallpier
//
//  Manages wallpaper cycling logic including queue, timer, and navigation
//

import Foundation
import Combine
import OSLog

/// Manages the cycling queue, timer, and navigation logic for wallpaper changes
@MainActor
final class ImageCycleManager {
    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "ImageCycleManager")

    // MARK: - Configuration

    private var configuration = CycleConfiguration()

    // MARK: - Timer Management

    private var cycleTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    // MARK: - Public State

    /// Current image in the cycle
    var currentImage: ImageFile? {
        configuration.currentImage
    }

    /// Current index in the cycle
    var currentIndex: Int {
        configuration.currentIndex
    }

    /// Whether cycling is active
    var isActive: Bool {
        configuration.isActive
    }

    /// Cycle progress (0.0 to 1.0)
    var cycleProgress: Double {
        configuration.cycleProgress
    }

    /// Whether can advance to next image
    var canAdvance: Bool {
        configuration.canAdvance
    }

    /// Whether can go back to previous image
    var canGoBack: Bool {
        configuration.canGoBack
    }

    // MARK: - Initialization

    init() {
        logger.info("ImageCycleManager initialized")
    }

    // Note: deinit removed as stopTimer() is MainActor-isolated and can't be called synchronously

    // MARK: - Queue Management

    /// Updates the cycling queue with new images
    /// - Parameters:
    ///   - images: The array of images to cycle through
    ///   - preservePosition: Whether to preserve the current position in the queue
    func updateQueue(_ images: [ImageFile], preservePosition: Bool = false) {
        configuration.updateQueue(images, preservePosition: preservePosition)
        logger.debug("Queue updated with \(images.count) images")
    }

    /// Shuffles the cycling queue
    func shuffleQueue() {
        configuration.shuffleQueue()
        logger.debug("Queue shuffled")
    }

    /// Sorts the cycling queue by the specified order
    /// - Parameter order: The sort order to apply
    func sortQueue(_ order: ImageSortOrder) {
        configuration.sortQueue(order)
        logger.debug("Queue sorted by \(String(describing: order))")
    }

    /// Resets the cycling queue
    func reset() {
        configuration = CycleConfiguration()
        logger.debug("Cycle configuration reset")
    }

    // MARK: - Navigation

    /// Advances to the next image in the cycle
    /// - Returns: The next image, or nil if unavailable
    func advanceToNext() -> ImageFile? {
        let nextImage = configuration.advanceToNext()
        if nextImage != nil {
            let index = configuration.currentIndex
            logger.debug("Advanced to next image at index \(index)")
        }
        return nextImage
    }

    /// Goes back to the previous image in the cycle
    /// - Returns: The previous image, or nil if unavailable
    func goToPrevious() -> ImageFile? {
        let prevImage = configuration.goToPrevious()
        if prevImage != nil {
            let index = configuration.currentIndex
            logger.debug("Went back to previous image at index \(index)")
        }
        return prevImage
    }

    // MARK: - Timer Management

    /// Starts the cycling timer
    /// - Parameters:
    ///   - interval: Time interval between cycles in seconds
    ///   - onTick: Closure to call on each timer tick
    ///   - updateTimeRemaining: Closure to update remaining time (called every second)
    func startTimer(
        interval: TimeInterval,
        onTick: @escaping () async -> Void,
        updateTimeRemaining: @escaping (TimeInterval) -> Void
    ) {
        stopTimer()

        // Validate interval
        guard interval.isFinite && interval > 0 && interval <= 86400 else {
            logger.error("Invalid cycling interval: \(interval). Must be between 0 and 86400 seconds.")
            return
        }

        configuration.isActive = true

        // Start main cycle task
        cycleTask = Task { [weak self] in
            guard let self else { return }

            // Set initial time remaining
            await MainActor.run {
                updateTimeRemaining(interval)
            }

            // Start countdown
            await self.startCountdownTimer(interval: interval, updateTimeRemaining: updateTimeRemaining)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }

                await onTick()

                await MainActor.run {
                    updateTimeRemaining(interval)
                }
            }
        }

        logger.info("Cycle timer started with interval: \(interval)s")
    }

    /// Starts the countdown timer for UI updates
    private func startCountdownTimer(
        interval: TimeInterval,
        updateTimeRemaining: @escaping (TimeInterval) -> Void
    ) async {
        stopCountdownTimer()

        countdownTask = Task { [weak self] in
            guard let self else { return }
            var timeRemaining = interval

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                } catch {
                    break
                }

                await MainActor.run { [self] in // Explicitly capture self
                    guard self.configuration.isActive else { return }
                    timeRemaining = max(0, timeRemaining - 1)
                    if timeRemaining <= 0 {
                        timeRemaining = interval
                    }
                    updateTimeRemaining(timeRemaining)
                }
            }
        }
    }

    /// Stops the cycling timer
    func stopTimer() {
        cycleTask?.cancel()
        cycleTask = nil
        stopCountdownTimer()
        configuration.isActive = false
        logger.debug("Cycle timer stopped")
    }

    /// Stops the countdown timer
    private func stopCountdownTimer() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// Restarts the timer with a new interval
    /// - Parameters:
    ///   - interval: New time interval
    ///   - onTick: Closure to call on each timer tick
    ///   - updateTimeRemaining: Closure to update remaining time
    func restartTimer(
        interval: TimeInterval,
        onTick: @escaping () async -> Void,
        updateTimeRemaining: @escaping (TimeInterval) -> Void
    ) {
        if configuration.isActive {
            startTimer(interval: interval, onTick: onTick, updateTimeRemaining: updateTimeRemaining)
            logger.debug("Cycle timer restarted with new interval: \(interval)s")
        }
    }
}
