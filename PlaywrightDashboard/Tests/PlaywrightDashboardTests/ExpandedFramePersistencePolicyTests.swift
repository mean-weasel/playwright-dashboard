import Testing

@testable import PlaywrightDashboard

@Suite("ExpandedFramePersistencePolicy")
struct ExpandedFramePersistencePolicyTests {

  @Test("first screencast frame is persisted for save and history")
  func firstFramePersists() {
    #expect(
      ExpandedFramePersistencePolicy.shouldPersist(
        hasPersistedFrame: false,
        framesSinceLastPersist: 1
      ))
  }

  @Test("subsequent screencast frames persist on cadence")
  func subsequentFramesPersistOnCadence() {
    #expect(
      !ExpandedFramePersistencePolicy.shouldPersist(
        hasPersistedFrame: true,
        framesSinceLastPersist: 29
      ))
    #expect(
      ExpandedFramePersistencePolicy.shouldPersist(
        hasPersistedFrame: true,
        framesSinceLastPersist: 30
      ))
  }
}
