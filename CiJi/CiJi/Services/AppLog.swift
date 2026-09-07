import Foundation
import os

enum AppLog {
    private static let logger = Logger(subsystem: "app.ciji.mac", category: "App")

    /// Prints to Xcode console (View → Debug Area → Activate Console) and OSLog.
    static func console(_ message: String, category: String = "App") {
        let line = "[词笺/\(category)] \(message)"
        print(line)
        logger.log("\(line, privacy: .public)")
    }
}
