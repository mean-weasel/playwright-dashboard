import OSLog
import SwiftData

private let modelContainerLogger = Logger(
  subsystem: "PlaywrightDashboard", category: "ModelContainer")

struct ModelContainerCreation {
  let container: ModelContainer
  let usedFallback: Bool
  let persistenceErrorDescription: String?
}

/// Thrown when both the persistent store and the in-memory fallback fail to
/// initialize. Indicates the app cannot proceed and should surface the failure
/// to the user before terminating.
struct ModelContainerInitFailure: Error, LocalizedError {
  let persistentError: String
  let fallbackError: String

  var errorDescription: String? {
    "Unable to initialize SwiftData container. Persistent store failed: "
      + "\(persistentError). In-memory fallback also failed: \(fallbackError)."
  }
}

enum ModelContainerFactory {
  @MainActor private(set) static var lastCreationUsedFallback = false

  @MainActor
  static func make() throws -> ModelContainer {
    try makeWithDiagnostics().container
  }

  @MainActor
  static func makeWithDiagnostics() throws -> ModelContainerCreation {
    try make(
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
  static func makeInMemory() throws -> ModelContainerCreation {
    try make(
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
  static func makeWithCustomStore(at directory: URL) throws -> ModelContainerCreation {
    let storeURL = directory.appendingPathComponent("playwright-dashboard.store")
    return try make(
      persistent: {
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: storeURL)
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
  ) throws -> ModelContainerCreation {
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
      } catch let fallbackError {
        lastCreationUsedFallback = false
        modelContainerLogger.error(
          "In-memory SwiftData fallback also failed: \(fallbackError.localizedDescription)"
        )
        throw ModelContainerInitFailure(
          persistentError: persistenceErrorDescription,
          fallbackError: fallbackError.localizedDescription
        )
      }
    }
  }
}
