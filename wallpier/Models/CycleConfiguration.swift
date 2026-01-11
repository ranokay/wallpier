//
//  CycleConfiguration.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import Foundation

/// Configuration for wallpaper cycling behavior
struct CycleConfiguration: Codable, Sendable {
    /// Current cycling session identifier
    let sessionId: UUID

    /// List of images in the current cycling session
    var imageQueue: [ImageFile]

    /// Current index in the image queue
    var currentIndex: Int

    /// Whether cycling is currently active
    var isActive: Bool

    /// When the current image was set
    var currentImageSetTime: Date?

    /// Session statistics
    var statistics: CycleStatistics

    /// Cycling history (limited to last 100 changes)
    var history: [CycleHistoryEntry]

    init(images: [ImageFile] = []) {
        self.sessionId = UUID()
        self.imageQueue = images
        self.currentIndex = 0
        self.isActive = false
        self.currentImageSetTime = nil
        self.statistics = CycleStatistics()
        self.history = []
    }

    /// Current image file, if available
    var currentImage: ImageFile? {
        guard currentIndex >= 0 && currentIndex < imageQueue.count else {
            return nil
        }
        return imageQueue[currentIndex]
    }

    /// Next image file, if available
    var nextImage: ImageFile? {
        let nextIndex = (currentIndex + 1) % imageQueue.count
        guard nextIndex >= 0 && nextIndex < imageQueue.count else {
            return nil
        }
        return imageQueue[nextIndex]
    }

    /// Previous image file, if available
    var previousImage: ImageFile? {
        let prevIndex = currentIndex == 0 ? imageQueue.count - 1 : currentIndex - 1
        guard prevIndex >= 0 && prevIndex < imageQueue.count else {
            return nil
        }
        return imageQueue[prevIndex]
    }

    /// Progress through current cycle (0.0 to 1.0)
    var cycleProgress: Double {
        guard imageQueue.count > 0 else { return 0.0 }
        return Double(currentIndex) / Double(imageQueue.count)
    }

    /// Whether we can advance to the next image
    var canAdvance: Bool {
        return !imageQueue.isEmpty
    }

    /// Whether we can go back to the previous image
    var canGoBack: Bool {
        return !imageQueue.isEmpty
    }
}

// MARK: - Navigation Methods

extension CycleConfiguration {
    /// Advances to the next image in the queue
    mutating func advanceToNext() -> ImageFile? {
        guard canAdvance else { return nil }

        // Record in history
        if let currentImage = self.currentImage {
            addToHistory(currentImage, action: .displayed)
        }

        // Advance index
        currentIndex = (currentIndex + 1) % imageQueue.count
        currentImageSetTime = Date()

        // Update statistics
        statistics.incrementImageChanges()

        return currentImage
    }

    /// Goes back to the previous image
    mutating func goToPrevious() -> ImageFile? {
        guard canGoBack else { return nil }

        // Record in history
        if let currentImage = self.currentImage {
            addToHistory(currentImage, action: .skipped)
        }

        // Go back
        currentIndex = currentIndex == 0 ? imageQueue.count - 1 : currentIndex - 1
        currentImageSetTime = Date()

        // Update statistics
        statistics.incrementImageChanges()

        return currentImage
    }

    /// Jumps to a specific image by index
    mutating func jumpToImage(at index: Int) -> ImageFile? {
        guard index >= 0 && index < imageQueue.count else { return nil }

        // Record in history
        if let currentImage = self.currentImage {
            addToHistory(currentImage, action: .skipped)
        }

        currentIndex = index
        currentImageSetTime = Date()

        // Update statistics
        statistics.incrementImageChanges()

        return currentImage
    }

    /// Jumps to the specified image in the queue if it exists.
    /// - Parameter imageFile: The image to jump to.
    /// - Returns: `true` if the image was found and the jump was successful; otherwise, `false`.
    mutating func jumpToImage(_ imageFile: ImageFile) -> Bool {
        guard let index = imageQueue.firstIndex(of: imageFile) else { return false }
        return jumpToImage(at: index) != nil
    }

    /// Randomly shuffles the image queue and sets the current index to a random position in the shuffled queue.
    /// Increments the shuffle count in the session statistics.
    mutating func shuffleQueue() {
        guard !imageQueue.isEmpty else { return }

        // Use a properly seeded random number generator for true randomization
        var rng = SystemRandomNumberGenerator()

        // Perform Fisher-Yates shuffle for better randomization
        for i in (1..<imageQueue.count).reversed() {
            let j = Int.random(in: 0...i, using: &rng)
            imageQueue.swapAt(i, j)
        }

        // Start at a random position in the shuffled queue (not always 0)
        currentIndex = Int.random(in: 0..<imageQueue.count, using: &rng)

        statistics.incrementShuffle()
    }
}

// MARK: - Queue Management

extension CycleConfiguration {
    /// Updates the image queue with new images
    mutating func updateQueue(_ newImages: [ImageFile], preservePosition: Bool = true) {
        let previousCurrent = preservePosition ? currentImage : nil

        imageQueue = newImages

        // Try to maintain position if preservePosition is true
        if preservePosition, let previous = previousCurrent {
            if let newIndex = imageQueue.firstIndex(of: previous) {
                currentIndex = newIndex
            } else {
                currentIndex = 0
            }
        } else {
            currentIndex = 0
        }

        // Ensure index is valid
        if currentIndex >= imageQueue.count {
            currentIndex = max(0, imageQueue.count - 1)
        }

        statistics.lastQueueUpdate = Date()
    }

    /// Removes specific images from the queue
    mutating func removeImages(_ imagesToRemove: [ImageFile]) {
        let currentImage = self.currentImage

        imageQueue.removeAll { imagesToRemove.contains($0) }

        // Adjust current index
        if let current = currentImage, let newIndex = imageQueue.firstIndex(of: current) {
            currentIndex = newIndex
        } else {
            currentIndex = min(currentIndex, max(0, imageQueue.count - 1))
        }
    }

    /// Adds new images to the queue
    mutating func addImages(_ newImages: [ImageFile]) {
        imageQueue.append(contentsOf: newImages)
        statistics.lastQueueUpdate = Date()
    }

    /// Sorts the queue according to the specified order
    mutating func sortQueue(_ sortOrder: ImageSortOrder) {
        let currentImage = self.currentImage

        switch sortOrder {
        case .alphabetical:
            imageQueue.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .dateModified:
            imageQueue.sort { $0.modificationDate > $1.modificationDate }
        case .dateAdded:
            // For date added, we'll use the order they were scanned
            break
        case .fileSize:
            imageQueue.sort { $0.size > $1.size }
        case .random:
            imageQueue.shuffle()
        }

        // Restore current position
        if let current = currentImage, let newIndex = imageQueue.firstIndex(of: current) {
            currentIndex = newIndex
        } else {
            currentIndex = 0
        }
    }
}

// MARK: - History Management

extension CycleConfiguration {
    /// Adds an entry to the cycling history
    private mutating func addToHistory(_ imageFile: ImageFile, action: CycleAction) {
        let entry = CycleHistoryEntry(
            imageFile: imageFile,
            timestamp: Date(),
            action: action,
            sessionId: sessionId
        )

        history.append(entry)

        // Keep only last 100 entries
        if history.count > 100 {
            history.removeFirst()
        }
    }

    /// Gets recent history entries
    func getRecentHistory(limit: Int = 10) -> [CycleHistoryEntry] {
        return Array(history.suffix(limit))
    }
}

// MARK: - Supporting Types

/// Statistics for the current cycling session
struct CycleStatistics: Codable, Sendable {
    /// Session start time
    let sessionStartTime: Date

    /// Total number of image changes in this session
    var totalImageChanges: Int

    /// Total number of shuffles performed
    var totalShuffles: Int

    /// Last time the queue was updated
    var lastQueueUpdate: Date?

    /// Session duration
    var sessionDuration: TimeInterval {
        return Date().timeIntervalSince(sessionStartTime)
    }

    init() {
        self.sessionStartTime = Date()
        self.totalImageChanges = 0
        self.totalShuffles = 0
        self.lastQueueUpdate = nil
    }

    mutating func incrementImageChanges() {
        totalImageChanges += 1
    }

    mutating func incrementShuffle() {
        totalShuffles += 1
    }
}

/// Actions that can be performed on images during cycling
enum CycleAction: String, Codable {
    case displayed = "displayed"
    case skipped = "skipped"
    case manual = "manual"
    case error = "error"

    var displayName: String {
        switch self {
        case .displayed:
            return "Displayed"
        case .skipped:
            return "Skipped"
        case .manual:
            return "Manual"
        case .error:
            return "Error"
        }
    }
}

/// Entry in the cycling history
struct CycleHistoryEntry: Codable, Identifiable {
    let id: UUID
    let imageFile: ImageFile
    let timestamp: Date
    let action: CycleAction
    let sessionId: UUID

    init(imageFile: ImageFile, timestamp: Date, action: CycleAction, sessionId: UUID) {
        self.id = UUID()
        self.imageFile = imageFile
        self.timestamp = timestamp
        self.action = action
        self.sessionId = sessionId
    }

    /// Time elapsed since this entry
    var timeElapsed: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }

    /// Human-readable time description
    var timeDescription: String {
        let elapsed = timeElapsed
        if elapsed < 60 {
            return "\(Int(elapsed))s ago"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        } else {
            return "\(Int(elapsed / 3600))h ago"
        }
    }
}

// MARK: - Validation and Utility

extension CycleConfiguration {
    /// Validates the configuration state
    func validate() -> [String] {
        var errors: [String] = []

        if currentIndex < 0 || currentIndex >= imageQueue.count {
            errors.append(
                "Current index \(currentIndex) is out of bounds for queue size \(imageQueue.count)")
        }

        // Validate that all images in queue are accessible
        let inaccessibleImages = imageQueue.filter { !$0.isAccessible }
        if !inaccessibleImages.isEmpty {
            errors.append("\(inaccessibleImages.count) images in queue are no longer accessible")
        }

        return errors
    }

    /// Cleans up inaccessible images from the queue
    mutating func cleanupInaccessibleImages() -> Int {
        let originalCount = imageQueue.count
        removeImages(imageQueue.filter { !$0.isAccessible })
        return originalCount - imageQueue.count
    }

    /// Resets the configuration to initial state
    mutating func reset() {
        currentIndex = 0
        isActive = false
        currentImageSetTime = nil
        statistics = CycleStatistics()
        history.removeAll()
    }
}

// MARK: - Debugging and Display

extension CycleConfiguration: CustomStringConvertible {
    var description: String {
        return """
            CycleConfiguration(
                sessionId: \(sessionId),
                imageCount: \(imageQueue.count),
                currentIndex: \(currentIndex),
                isActive: \(isActive),
                progress: \(String(format: "%.1f", cycleProgress * 100))%
            )
            """
    }
}
