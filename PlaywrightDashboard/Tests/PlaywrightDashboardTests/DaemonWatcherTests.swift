import Foundation
import Testing

@testable import PlaywrightDashboard

@MainActor
@Suite("DaemonWatcher")
struct DaemonWatcherTests {

  @Test("scanSessionFiles finds sorted session files in daemon hash directories")
  func scanSessionFilesFindsSortedSessions() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try writeFile("{}", at: root, components: ["hash-z", "z.session"])
    _ = try writeFile("{}", at: root, components: ["hash-a", "a.session"])
    _ = try writeFile("{}", at: root, components: ["hash-a", "notes.txt"])
    _ = try writeFile("{}", at: root, components: ["hash-user-data", "ignored.session"])

    let watcher = DaemonWatcher(daemonDirectory: root)
    watcher.scanSessionFiles()

    #expect(
      relativePaths(watcher.sessionFiles, root: root) == ["hash-a/a.session", "hash-z/z.session"])
  }

  @Test("scanSessionFiles clears sessions when daemon directory is missing")
  func scanSessionFilesClearsMissingDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let watcher = DaemonWatcher(daemonDirectory: root)

    watcher.scanSessionFiles()

    #expect(watcher.sessionFiles.isEmpty)
  }

  @Test("scanSessionFiles ignores top-level session files and non-directory entries")
  func scanSessionFilesIgnoresTopLevelFiles() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try writeFile("{}", at: root, components: ["top-level.session"])
    _ = try writeFile("not a directory", at: root, components: ["hash-file"])
    _ = try writeFile("{}", at: root, components: ["hash-dir", "nested.session"])

    let watcher = DaemonWatcher(daemonDirectory: root)
    watcher.scanSessionFiles()

    #expect(relativePaths(watcher.sessionFiles, root: root) == ["hash-dir/nested.session"])
  }

  @Test("start performs initial scan when daemon directory exists")
  func startPerformsInitialScan() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try writeFile("{}", at: root, components: ["hash-a", "startup.session"])

    let watcher = DaemonWatcher(daemonDirectory: root)
    watcher.start()
    defer { watcher.stop() }

    #expect(relativePaths(watcher.sessionFiles, root: root) == ["hash-a/startup.session"])
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func relativePaths(_ urls: [URL], root: URL) -> [String] {
    let rootPath = root.resolvingSymlinksInPath().path
    return urls.map { url in
      let path = url.resolvingSymlinksInPath().path
      guard path.hasPrefix(rootPath + "/") else { return path }
      return String(path.dropFirst(rootPath.count + 1))
    }
  }

  @discardableResult
  private func writeFile(_ contents: String, at root: URL, components: [String]) throws -> URL {
    let url = components.reduce(root) { partial, component in
      partial.appendingPathComponent(component)
    }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
