import OSLog
import SwiftData

private let modelContainerLogger = Logger(
  subsystem: "PlaywrightDashboard", category: "ModelContainer")

enum ModelContainerFactory {
  @MainActor
  static func make() -> ModelContainer {
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
  static func make(
    persistent: () throws -> ModelContainer,
    fallback: () throws -> ModelContainer
  ) -> ModelContainer {
    do {
      return try persistent()
    } catch {
      modelContainerLogger.error(
        "Persistent SwiftData container failed, using in-memory store: \(error.localizedDescription)"
      )
      do {
        return try fallback()
      } catch {
        fatalError("Failed to create fallback SwiftData model container: \(error)")
      }
    }
  }
}
