import Foundation
import SwiftData

@testable import PlaywrightDashboard

@MainActor
final class TestSessionFileProvider {
  var files: [URL]

  init(files: [URL]) {
    self.files = files
  }
}

@MainActor
final class TestSessionHarness {
  let root: URL
  let context: ModelContext
  private let container: ModelContainer

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    container = try ModelContainer(for: SessionRecord.self, configurations: configuration)
    context = container.mainContext
  }

  func workspace(_ name: String) -> String {
    root
      .appendingPathComponent("my-app", isDirectory: true)
      .appendingPathComponent(".claude", isDirectory: true)
      .appendingPathComponent("worktrees", isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
      .path
  }

  func writeSession(name: String, workspace: String, port: Int = 9222) throws -> URL {
    let url = root.appendingPathComponent("\(name).session")
    let config = SessionFileConfig(
      name: name,
      version: "1.0",
      timestamp: 0,
      socketPath: root.appendingPathComponent("\(name).sock").path,
      workspaceDir: workspace,
      cli: .init(),
      browser: .init(
        browserName: "chromium",
        launchOptions: .init(
          headless: true,
          chromiumSandbox: false,
          args: ["--remote-debugging-port=\(port)"]
        )
      )
    )
    let data = try JSONEncoder().encode(config)
    try data.write(to: url)
    return url
  }
}
