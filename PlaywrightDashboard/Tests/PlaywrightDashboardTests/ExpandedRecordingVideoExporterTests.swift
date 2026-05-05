import AppKit
import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("ExpandedRecordingVideoExporter")
struct ExpandedRecordingVideoExporterTests {

  @Test("exports frames to MP4 without removing raw frames")
  func exportsFramesToMP4() async throws {
    let directory = try makeRecordingDirectory(frameCount: 2)
    defer { try? FileManager.default.removeItem(at: directory) }

    let outputURL = try await ExpandedRecordingVideoExporter().exportMP4(from: directory)

    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    #expect((try Data(contentsOf: outputURL)).count > 0)
    #expect(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("frame-000001.jpg").path))
  }

  @Test("empty manifest fails cleanly")
  func emptyManifestFailsCleanly() async throws {
    let directory = try makeRecordingDirectory(frameCount: 0)
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      _ = try await ExpandedRecordingVideoExporter().exportMP4(from: directory)
      Issue.record("Expected export to fail")
    } catch let error as ExpandedRecordingVideoExporter.ExportError {
      #expect(error == .noFrames)
    }
  }

  @Test("missing frame reports useful error")
  func missingFrameReportsUsefulError() async throws {
    let directory = try makeRecordingDirectory(frameCount: 1)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.removeItem(at: directory.appendingPathComponent("frame-000001.jpg"))

    do {
      _ = try await ExpandedRecordingVideoExporter().exportMP4(from: directory)
      Issue.record("Expected export to fail")
    } catch let error as ExpandedRecordingVideoExporter.ExportError {
      #expect(error == .invalidFrame("frame-000001.jpg"))
    }
  }

  private func makeRecordingDirectory(frameCount: Int) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var frames: [ExpandedRecordingManifest.Frame] = []
    for offset in 0..<frameCount {
      let index = offset + 1
      let filename = String(format: "frame-%06d.jpg", index)
      let data = try jpegData(red: CGFloat(index) / CGFloat(max(frameCount, 1)))
      try data.write(to: directory.appendingPathComponent(filename))
      frames.append(
        ExpandedRecordingManifest.Frame(
          index: index,
          filename: filename,
          timestamp: now.addingTimeInterval(Double(offset) / 10),
          url: nil,
          title: nil
        ))
    }

    let manifest = ExpandedRecordingManifest(
      version: 1,
      sessionId: "session",
      displayName: "Session",
      targetId: nil,
      initialURL: nil,
      initialTitle: nil,
      finalURL: nil,
      finalTitle: nil,
      startedAt: now,
      endedAt: now.addingTimeInterval(1),
      frameCount: frames.count,
      frames: frames
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
    return directory
  }

  private func jpegData(red: CGFloat) throws -> Data {
    let image = NSImage(size: NSSize(width: 24, height: 16))
    image.lockFocus()
    NSColor(calibratedRed: red, green: 0.2, blue: 0.8, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 24, height: 16).fill()
    image.unlockFocus()

    guard
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    else {
      throw ExpandedRecordingVideoExporter.ExportError.invalidFrame("generated")
    }
    return data
  }
}
