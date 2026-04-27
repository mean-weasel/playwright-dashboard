import Foundation

/// Lifecycle state of a Playwright browser session.
enum SessionStatus: String, Codable {
    case active   // CDP connected, page navigated
    case idle     // CDP connected, about:blank or no activity
    case stale    // idle > 2 minutes
    case closed   // session file gone
}
