import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("SessionFileScanner")
struct SessionFileScannerTests {

  @Test("Skips files above the configured byte limit before reading")
  func skipsOversizedFiles() async throws {
    let root = try makeTemporaryDirectory()
    let url = root.appendingPathComponent("large.session")
    try String(repeating: "x", count: 32).write(to: url, atomically: true, encoding: .utf8)

    let scanner = SessionFileScanner(maxSessionFileBytes: 8)
    let result = await scanner.scan([url])

    #expect(result.configs.isEmpty)
    #expect(result.skippedFiles["large.session"]?.contains("file size") == true)
    #expect(result.errors["large.session"]?.contains("Skipped session file") == true)
    #expect(result.unresolvedSessionIds == ["large"])
  }

  @Test("Skips files beyond the configured scan limit")
  func skipsFilesBeyondScanLimit() async throws {
    let root = try makeTemporaryDirectory()
    let first = try writeSession(root: root, name: "first")
    let second = try writeSession(root: root, name: "second")

    let scanner = SessionFileScanner(maxFilesPerScan: 1)
    let result = await scanner.scan([first, second])

    #expect(result.configs.map(\.name) == ["first"])
    #expect(result.skippedFiles["second.session"]?.contains("scan limit") == true)
    #expect(result.errors["second.session"]?.contains("Skipped session file") == true)
    #expect(result.unresolvedSessionIds == ["second"])
  }

  private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func writeSession(root: URL, name: String) throws -> URL {
    let url = root.appendingPathComponent("\(name).session")
    let config = SessionFileConfig(
      name: name,
      version: "1.0",
      timestamp: 0,
      socketPath: root.appendingPathComponent("\(name).sock").path,
      workspaceDir: root.path,
      cli: .init(),
      browser: .init(
        browserName: "chromium",
        launchOptions: .init(
          headless: true,
          chromiumSandbox: false,
          cdpPort: 9222
        )
      )
    )
    let data = try JSONEncoder().encode(config)
    try data.write(to: url)
    return url
  }
}
