import Foundation
import SwiftData
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("ModelContainerFactory")
struct ModelContainerFactoryTests {

  @Test("Falls back to in-memory container when persistent creation fails")
  func fallsBackToInMemoryContainer() throws {
    var didUseFallback = false

    let creation = try ModelContainerFactory.make(
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
    #expect(creation.persistenceErrorDescription == "persistentFailed")
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

    let creation = try ModelContainerFactory.make(
      persistent: {
        try ModelContainer(for: SessionRecord.self, configurations: configuration)
      },
      fallback: {
        Issue.record("Did not expect fallback")
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
      }
    )

    #expect(creation.usedFallback == false)
    #expect(creation.persistenceErrorDescription == nil)
    #expect(ModelContainerFactory.lastCreationUsedFallback == false)
  }

  @Test("Throws when both persistent and fallback fail")
  func throwsWhenBothPersistentAndFallbackFail() {
    #expect(throws: ModelContainerInitFailure.self) {
      _ = try ModelContainerFactory.make(
        persistent: { throw TestError.persistentFailed },
        fallback: { throw TestError.fallbackFailed }
      )
    }
    #expect(ModelContainerFactory.lastCreationUsedFallback == false)
  }

  private enum TestError: LocalizedError {
    case persistentFailed
    case fallbackFailed

    var errorDescription: String? {
      switch self {
      case .persistentFailed:
        return "persistentFailed"
      case .fallbackFailed:
        return "fallbackFailed"
      }
    }
  }
}
