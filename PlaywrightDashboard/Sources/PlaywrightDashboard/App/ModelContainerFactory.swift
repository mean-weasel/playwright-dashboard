import OSLog
import SwiftData

private let modelContainerLogger = Logger(
  subsystem: "PlaywrightDashboard", category: "ModelContainer")

struct ModelContainerCreation {
  let container: ModelContainer
  let usedFallback: Bool
  let persistenceErrorDescription: String?
}

enum ModelContainerFactory {
  @MainActor private(set) static var lastCreationUsedFallback = false

  @MainActor
  static func make() -> ModelContainer {
    makeWithDiagnostics().container
  }

  @MainActor
  static func makeWithDiagnostics() -> ModelContainerCreation {
    make(
      persistent: {
        try ModelContainer(for: SessionRecord.self)
      },
      fallback: {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
      }
    )
  }

  @MainActor
  static func makeInMemory() -> ModelContainerCreation {
    make(
      persistent: {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
      },
      fallback: {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SessionRecord.self, configurations: configuration)
      }
    )
  }

  @MainActor
  static func make(
    persistent: () throws -> ModelContainer,
    fallback: () throws -> ModelContainer
  ) -> ModelContainerCreation {
    do {
      let container = try persistent()
      lastCreationUsedFallback = false
      return ModelContainerCreation(
        container: container,
        usedFallback: false,
        persistenceErrorDescription: nil
      )
    } catch {
      let persistenceErrorDescription = error.localizedDescription
      modelContainerLogger.error(
        "Persistent SwiftData container failed, using in-memory store: \(persistenceErrorDescription)"
      )
      do {
        let container = try fallback()
        lastCreationUsedFallback = true
        return ModelContainerCreation(
          container: container,
          usedFallback: true,
          persistenceErrorDescription: persistenceErrorDescription
        )
      } catch {
        lastCreationUsedFallback = false
        fatalError("Failed to create fallback SwiftData model container: \(error)")
      }
    }
  }
}
