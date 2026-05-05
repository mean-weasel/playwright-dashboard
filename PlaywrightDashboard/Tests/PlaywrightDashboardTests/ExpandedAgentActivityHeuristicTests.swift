import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("ExpandedAgentActivityHeuristic")
struct ExpandedAgentActivityHeuristicTests {

  @Test("does not warn outside control mode")
  func doesNotWarnOutsideControlMode() {
    #expect(
      !ExpandedAgentActivityHeuristic.shouldShowWarning(
        interactionEnabled: false,
        previousURL: "http://localhost:3000",
        previousTitle: "Before",
        newURL: "http://localhost:3001",
        newTitle: "After",
        lastLocalInteractionAt: nil
      ))
  }

  @Test("warns when page changes without recent local input")
  func warnsForExternalPageChange() {
    #expect(
      ExpandedAgentActivityHeuristic.shouldShowWarning(
        interactionEnabled: true,
        previousURL: "http://localhost:3000",
        previousTitle: "Before",
        newURL: "http://localhost:3001",
        newTitle: "After",
        lastLocalInteractionAt: nil
      ))
  }

  @Test("suppresses warning after local input")
  func suppressesRecentLocalInput() {
    let now = Date()

    #expect(
      !ExpandedAgentActivityHeuristic.shouldShowWarning(
        interactionEnabled: true,
        previousURL: "http://localhost:3000",
        previousTitle: "Before",
        newURL: "http://localhost:3001",
        newTitle: "After",
        lastLocalInteractionAt: now.addingTimeInterval(-1),
        now: now
      ))
  }
}
