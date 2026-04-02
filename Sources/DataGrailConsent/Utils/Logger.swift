import Foundation
import os.log

/// Log level for the DataGrail Consent SDK
public enum LogLevel: Int, Comparable {
    case none = 0   // No logging
    case error = 1  // Only errors
    case warn = 2   // Warnings + errors
    case info = 3   // Info + warnings + errors
    case debug = 4  // Debug + info + warnings + errors (most verbose)

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Logger for the DataGrail Consent SDK.
/// Default level is NONE (no logging in production).
/// Set the level property to enable logging for debugging.
enum Logger {
    private static let subsystem = "com.datagrail.consent"
    private static let log = OSLog(subsystem: subsystem, category: "DataGrailConsent")

    /// Current log level - controls which messages are logged
    static var logLevel: LogLevel = .none

    /// Log a debug message
    /// - Parameter message: The debug message to log
    static func debug(_ message: String) {
        guard logLevel >= .debug else { return }
        os_log("%{public}@", log: log, type: .debug, "[DEBUG] \(message)")
    }

    /// Log a warning message
    /// - Parameter message: The warning message to log
    static func warn(_ message: String) {
        guard logLevel >= .warn else { return }
        os_log("%{public}@", log: log, type: .default, "[WARN] \(message)")
    }

    /// Log an info message
    /// - Parameter message: The info message to log
    static func info(_ message: String) {
        guard logLevel >= .info else { return }
        os_log("%{public}@", log: log, type: .info, "[INFO] \(message)")
    }

    /// Log an error message
    /// - Parameter message: The error message to log
    static func error(_ message: String) {
        guard logLevel >= .error else { return }
        os_log("%{public}@", log: log, type: .error, "[ERROR] \(message)")
    }
}
