import Foundation
import Darwin
import OSLog

/// Allows opt-out of App Intents metadata extraction to suppress build-time warnings in CI/test runs.
enum AppIntentsMetadataController {
    static func apply(disableExtraction: Bool) {
        if disableExtraction {
            setenv("APPINTENTS_METADATA_DISABLED", "1", 1)
            UserDefaults.standard.set(true, forKey: "APPINTENTS_METADATA_DISABLED")
            Logger.appIntents.info("App Intents metadata extraction disabled via settings")
        } else {
            unsetenv("APPINTENTS_METADATA_DISABLED")
            UserDefaults.standard.set(false, forKey: "APPINTENTS_METADATA_DISABLED")
            Logger.appIntents.debug("App Intents metadata extraction enabled")
        }
    }
}
