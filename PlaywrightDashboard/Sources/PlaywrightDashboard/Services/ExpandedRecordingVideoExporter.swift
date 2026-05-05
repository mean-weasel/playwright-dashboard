import AVFoundation
import AppKit
import Foundation

actor ExpandedRecordingVideoExporter {
  private let fileManager: FileManager
  private let framesPerSecond: Int32

  init(fileManager: FileManager = .default, framesPerSecond: Int32 = 10) {
    self.fileManager = fileManager
    self.framesPerSecond = max(1, framesPerSecond)
  }

  func exportMP4(from recordingDirectory: URL) async throws -> URL {
    let manifest = try loadManifest(from: recordingDirectory)
    guard !manifest.frames.isEmpty else { throw ExportError.noFrames }

    let firstImage = try loadImage(
      recordingDirectory.appendingPathComponent(manifest.frames[0].filename))
    let size = CGSize(width: firstImage.width, height: firstImage.height)
    guard size.width > 0, size.height > 0 else { throw ExportError.invalidFrameSize }

    let outputURL = recordingDirectory.appendingPathComponent("recording.mp4")
    if fileManager.fileExists(atPath: outputURL.path) {
      try fileManager.removeItem(at: outputURL)
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width),
        AVVideoHeightKey: Int(size.height),
      ])
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height),
      ])

    guard writer.canAdd(input) else { throw ExportError.writerSetupFailed }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? ExportError.writerSetupFailed }
    writer.startSession(atSourceTime: .zero)

    do {
      try await appendFrames(
        manifest.frames,
        from: recordingDirectory,
        size: size,
        input: input,
        adaptor: adaptor
      )
      input.markAsFinished()
      try await finish(writer)
      return outputURL
    } catch {
      writer.cancelWriting()
      try? fileManager.removeItem(at: outputURL)
      throw error
    }
  }

  private func appendFrames(
    _ frames: [ExpandedRecordingManifest.Frame],
    from directory: URL,
    size: CGSize,
    input: AVAssetWriterInput,
    adaptor: AVAssetWriterInputPixelBufferAdaptor
  ) async throws {
    for (offset, frame) in frames.enumerated() {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(for: .milliseconds(10))
      }
      let image = try loadImage(directory.appendingPathComponent(frame.filename))
      let buffer = try makePixelBuffer(from: image, size: size)
      let time = CMTime(value: CMTimeValue(offset), timescale: framesPerSecond)
      guard adaptor.append(buffer, withPresentationTime: time) else {
        throw ExportError.appendFailed
      }
    }
  }

  private func loadManifest(from directory: URL) throws -> ExpandedRecordingManifest {
    let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(ExpandedRecordingManifest.self, from: data)
  }

  private func loadImage(_ url: URL) throws -> CGImage {
    guard let image = NSImage(contentsOf: url) else {
      throw ExportError.invalidFrame(url.lastPathComponent)
    }
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
      throw ExportError.invalidFrame(url.lastPathComponent)
    }
    return cgImage
  }

  private func makePixelBuffer(from image: CGImage, size: CGSize) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32ARGB,
      nil,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else { throw ExportError.pixelBufferFailed }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let context = CGContext(
        data: baseAddress,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
      )
    else {
      throw ExportError.pixelBufferFailed
    }

    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    context.interpolationQuality = .high
    context.draw(image, in: aspectFitRect(image: image, target: size))
    return pixelBuffer
  }

  private func aspectFitRect(image: CGImage, target: CGSize) -> CGRect {
    let scale = min(target.width / CGFloat(image.width), target.height / CGFloat(image.height))
    let width = CGFloat(image.width) * scale
    let height = CGFloat(image.height) * scale
    return CGRect(
      x: (target.width - width) / 2,
      y: (target.height - height) / 2,
      width: width,
      height: height
    )
  }

  private func finish(_ writer: AVAssetWriter) async throws {
    await withCheckedContinuation { continuation in
      writer.finishWriting {
        continuation.resume()
      }
    }
    guard writer.status == .completed else {
      throw writer.error ?? ExportError.finishFailed
    }
  }

  enum ExportError: LocalizedError, Equatable {
    case noFrames
    case invalidFrameSize
    case invalidFrame(String)
    case writerSetupFailed
    case pixelBufferFailed
    case appendFailed
    case finishFailed

    var errorDescription: String? {
      switch self {
      case .noFrames: "Recording has no frames to export."
      case .invalidFrameSize: "Recording frames have an invalid size."
      case .invalidFrame(let filename): "Could not read recording frame \(filename)."
      case .writerSetupFailed: "Could not create the MP4 writer."
      case .pixelBufferFailed: "Could not prepare a video frame buffer."
      case .appendFailed: "Could not append a frame to the MP4."
      case .finishFailed: "Could not finish the MP4 export."
      }
    }
  }
}
