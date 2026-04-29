#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.icns")
let fileManager = FileManager.default
let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(
  "playwright-dashboard-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = tempRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(
  at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

defer { try? fileManager.removeItem(at: tempRoot) }

let iconFiles: [(name: String, size: Int)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1024),
]

for iconFile in iconFiles {
  let image = NSImage(size: NSSize(width: iconFile.size, height: iconFile.size))
  image.lockFocus()
  drawIcon(size: CGFloat(iconFile.size))
  image.unlockFocus()

  guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
  else {
    throw IconGenerationError.pngEncodingFailed(iconFile.name)
  }

  try pngData.write(to: iconsetURL.appendingPathComponent(iconFile.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
  "-c",
  "icns",
  iconsetURL.path,
  "-o",
  outputURL.path,
]

try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
  throw IconGenerationError.iconutilFailed(process.terminationStatus)
}

private func drawIcon(size: CGFloat) {
  let bounds = CGRect(x: 0, y: 0, width: size, height: size)
  let cornerRadius = size * 0.22
  let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

  NSGraphicsContext.current?.cgContext.saveGState()
  path.addClip()

  let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.32, alpha: 1),
  ])
  gradient?.draw(in: bounds, angle: 315)

  let browserRect = bounds.insetBy(dx: size * 0.16, dy: size * 0.18)
  let browserPath = NSBezierPath(
    roundedRect: browserRect, xRadius: size * 0.055, yRadius: size * 0.055)
  NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
  browserPath.fill()

  let toolbarHeight = size * 0.15
  let toolbarRect = CGRect(
    x: browserRect.minX,
    y: browserRect.maxY - toolbarHeight,
    width: browserRect.width,
    height: toolbarHeight)
  NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.94, alpha: 1).setFill()
  NSBezierPath(rect: toolbarRect).fill()

  let dotDiameter = size * 0.035
  for index in 0..<3 {
    let dotRect = CGRect(
      x: toolbarRect.minX + size * 0.045 + CGFloat(index) * dotDiameter * 1.65,
      y: toolbarRect.midY - dotDiameter / 2,
      width: dotDiameter,
      height: dotDiameter)
    NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(ovalIn: dotRect).fill()
  }

  let playRect = CGRect(
    x: browserRect.midX - size * 0.09,
    y: browserRect.midY - size * 0.13,
    width: size * 0.23,
    height: size * 0.24)
  let triangle = NSBezierPath()
  triangle.move(to: CGPoint(x: playRect.minX, y: playRect.minY))
  triangle.line(to: CGPoint(x: playRect.minX, y: playRect.maxY))
  triangle.line(to: CGPoint(x: playRect.maxX, y: playRect.midY))
  triangle.close()
  NSColor(calibratedRed: 0.00, green: 0.54, blue: 0.45, alpha: 1).setFill()
  triangle.fill()

  NSGraphicsContext.current?.cgContext.restoreGState()
}

private enum IconGenerationError: Error {
  case pngEncodingFailed(String)
  case iconutilFailed(Int32)
}
