import SwiftData
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("ModelContainerFactory")
struct ModelContainerFactoryTests {

  @Test("Falls back to in-memory container when persistent creation fails")
  func fallsBackToInMemoryContainer() throws {
    var didUseFallback = false

    let container = ModelContainerFactory.make(
      persistent: {
        throw TestError.persistentFailed
      },
      fallback: {
        didUseFallback = true
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
      }
    )

    #expect(didUseFallback)
    let record = SessionRecord(
      sessionId: "fallback",
      autoLabel: "Fallback",
      workspaceDir: "/tmp/fallback",
      cdpPort: 0,
      socketPath: "/tmp/fallback.sock"
    )
    container.mainContext.insert(record)
    try container.mainContext.save()
  }

  private enum TestError: Error {
    case persistentFailed
  }
}
