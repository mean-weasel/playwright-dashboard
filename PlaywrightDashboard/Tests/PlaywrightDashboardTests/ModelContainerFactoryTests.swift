import SwiftData
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("ModelContainerFactory")
struct ModelContainerFactoryTests {

  @Test("Falls back to in-memory container when persistent creation fails")
  func fallsBackToInMemoryContainer() throws {
    var didUseFallback = false

    let creation = ModelContainerFactory.make(
      persistent: {
        throw TestError.persistentFailed
      },
      fallback: {
        didUseFallback = true
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
      }
    )
    let container = creation.container

    #expect(didUseFallback)
    #expect(creation.usedFallback)
    #expect(ModelContainerFactory.lastCreationUsedFallback)
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

  @Test("Reports persistent container usage")
  func reportsPersistentContainerUsage() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

    let creation = ModelContainerFactory.make(
      persistent: {
        try ModelContainer(for: SessionRecord.self, configurations: configuration)
      },
      fallback: {
        Issue.record("Did not expect fallback")
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
      }
    )

    #expect(creation.usedFallback == false)
    #expect(ModelContainerFactory.lastCreationUsedFallback == false)
  }

  private enum TestError: Error {
    case persistentFailed
  }
}
