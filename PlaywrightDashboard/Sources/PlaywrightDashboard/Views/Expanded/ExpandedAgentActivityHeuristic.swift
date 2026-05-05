import Foundation

enum ExpandedAgentActivityHeuristic {
  static let localInputGrace: TimeInterval = 2
  static let warningDuration: Duration = .seconds(3)

  static func shouldShowWarning(
    interactionEnabled: Bool,
    previousURL: String?,
    previousTitle: String?,
    newURL: String?,
    newTitle: String?,
    lastLocalInteractionAt: Date?,
    now: Date = Date()
  ) -> Bool {
    guard interactionEnabled else { return false }
    guard previousURL != nil || previousTitle != nil else { return false }
    guard previousURL != newURL || previousTitle != newTitle else { return false }

    if let lastLocalInteractionAt,
      now.timeIntervalSince(lastLocalInteractionAt) < localInputGrace
    {
      return false
    }
    return true
  }
}
