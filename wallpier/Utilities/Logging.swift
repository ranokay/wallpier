import OSLog

// Centralized log categories to keep subsystem/category usage consistent
extension Logger {
    static let wallpaper = Logger(subsystem: "com.oxystack.wallpier", category: "wallpaper")
    static let cache = Logger(subsystem: "com.oxystack.wallpier", category: "cache")
    static let scanner = Logger(subsystem: "com.oxystack.wallpier", category: "scanner")
    static let settings = Logger(subsystem: "com.oxystack.wallpier", category: "settings")
    static let appIntents = Logger(subsystem: "com.oxystack.wallpier", category: "appintents")
}
