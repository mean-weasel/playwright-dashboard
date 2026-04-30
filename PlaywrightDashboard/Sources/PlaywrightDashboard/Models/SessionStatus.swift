import Foundation

/// Lifecycle state of a Playwright browser session.
enum SessionStatus: String, Codable {
  case active  // CDP connected, page navigated
  case idle  // CDP connected, about:blank or no activity
  case stale  // idle > 2 minutes
  case closing  // close requested, waiting for daemon confirmation
  case closeFailed  // close requested, daemon reported an error
  case closed  // session file gone

  var displayText: String {
    switch self {
    case .active: "Active"
    case .idle: "Idle"
    case .stale: "Stale"
    case .closing: "Closing"
    case .closeFailed: "Close Failed"
    case .closed: "Closed"
    }
  }
}
