import Foundation
import os.log

/// Logging utility for DataGrailConsent SDK
enum Logger {
    private static let subsystem = "com.datagrail.consent"
    private static let log = OSLog(subsystem: subsystem, category: "DataGrailConsent")

    /// Log a warning message
    /// - Parameter message: The warning message to log
    static func warn(_ message: String) {
        os_log("%{public}@", log: log, type: .default, "[WARN] \(message)")
    }

    /// Log an error message
    /// - Parameter message: The error message to log
    static func error(_ message: String) {
        os_log("%{public}@", log: log, type: .error, "[ERROR] \(message)")
    }

    /// Log an info message
    /// - Parameter message: The info message to log
    static func info(_ message: String) {
        os_log("%{public}@", log: log, type: .info, "[INFO] \(message)")
    }

    /// Log a debug message
    /// - Parameter message: The debug message to log
    static func debug(_ message: String) {
        os_log("%{public}@", log: log, type: .debug, "[DEBUG] \(message)")
    }
}
