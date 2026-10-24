import Foundation

enum DumpError: LocalizedError {
    case executableNotDumped
    case fridaNotRunning

    var errorDescription: String? {
        switch self {
        case .executableNotDumped: return "Failed to dump executable"
        case .fridaNotRunning: return "Frida server is not running on port 27042"
        }
    }
}
