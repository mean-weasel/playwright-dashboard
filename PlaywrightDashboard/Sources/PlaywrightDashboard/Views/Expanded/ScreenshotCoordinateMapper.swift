import Foundation

enum ScreenshotCoordinateMapper {
  static func imageFrame(containerSize: CGSize, imageSize: CGSize) -> CGRect {
    guard containerSize.width > 0, containerSize.height > 0,
      imageSize.width > 0, imageSize.height > 0
    else {
      return .zero
    }

    let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
      x: (containerSize.width - size.width) / 2,
      y: (containerSize.height - size.height) / 2,
      width: size.width,
      height: size.height
    )
  }

  static func browserPoint(localPoint: CGPoint, imageFrame: CGRect, imageSize: CGSize) -> CGPoint? {
    guard imageFrame.width > 0, imageFrame.height > 0,
      imageSize.width > 0, imageSize.height > 0,
      imageFrame.contains(localPoint)
    else {
      return nil
    }

    let x = (localPoint.x - imageFrame.minX) / imageFrame.width * imageSize.width
    let y = (localPoint.y - imageFrame.minY) / imageFrame.height * imageSize.height
    return CGPoint(x: x, y: y)
  }
}
