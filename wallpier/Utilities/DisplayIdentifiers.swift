import AppKit

/// Stable identifier for a display/screen
public struct ScreenID: Hashable, Equatable, Sendable {
    public let rawValue: String
}

/// Computes a stable ScreenID for a given NSScreen
public func makeScreenID(for screen: NSScreen) -> ScreenID {
    // Prefer localizedName if available; fall back to frame to disambiguate
    let name = screen.localizedName
    let frame = screen.frame
    let id = "\(name)-\(Int(frame.origin.x))x\(Int(frame.origin.y))-\(Int(frame.size.width))x\(Int(frame.size.height))"
    return ScreenID(rawValue: id)
}
