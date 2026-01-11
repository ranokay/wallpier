import Foundation
import AppKit

/// Controls per-screen cycling indices independent of the global queue
struct ScreenCycleController: Sendable {
    private(set) var indices: [ScreenID: Int] = [:]

    /// Check if there are no indices set
    var isEmpty: Bool {
        indices.isEmpty
    }

    /// Reset indices for a given set of screens, using shuffle or staggered starts
    mutating func reset(for screens: [NSScreen], imageCount: Int, shuffle: Bool) {
        indices.removeAll()
        guard imageCount > 0 else { return }
        for (index, screen) in screens.enumerated() {
            let sid = makeScreenID(for: screen)
            let startIndex: Int
            if shuffle {
                startIndex = Int.random(in: 0..<imageCount)
            } else {
                startIndex = index % imageCount
            }
            indices[sid] = startIndex
        }
    }

    /// Clears all indices - useful when stopping cycling
    mutating func clear() {
        indices.removeAll()
    }

    /// Ensure indices exist for the given screens
    mutating func ensureInitialized(for screens: [NSScreen], imageCount: Int, shuffle: Bool) {
        guard indices.isEmpty else { return }
        reset(for: screens, imageCount: imageCount, shuffle: shuffle)
    }

    /// Advance a screen's index to the next image
    mutating func advance(for screen: NSScreen, imageCount: Int) -> Int? {
        guard imageCount > 0 else { return nil }
        let sid = makeScreenID(for: screen)
        let current = indices[sid] ?? 0
        let next = (current + 1) % imageCount
        indices[sid] = next
        return next
    }

    /// Go back to the previous image for a screen
    mutating func goBack(for screen: NSScreen, imageCount: Int) -> Int? {
        guard imageCount > 0 else { return nil }
        let sid = makeScreenID(for: screen)
        let current = indices[sid] ?? 0
        let prev = current == 0 ? imageCount - 1 : current - 1
        indices[sid] = prev
        return prev
    }

    /// Get current index for a screen
    func currentIndex(for screen: NSScreen) -> Int? {
        let sid = makeScreenID(for: screen)
        return indices[sid]
    }
}

