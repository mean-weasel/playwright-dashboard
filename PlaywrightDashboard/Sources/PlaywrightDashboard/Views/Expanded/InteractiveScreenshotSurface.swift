import AppKit
import SwiftUI

struct InteractiveScreenshotSurface: View {
  let image: NSImage
  let interactionEnabled: Bool
  let onClick: (CGPoint) -> Void
  let onScroll: (CGPoint, CGFloat, CGFloat) -> Void
  let onKeyPress: (CDPClient.KeyEventInput) -> Void

  var body: some View {
    GeometryReader { proxy in
      let imageSize = image.size
      let imageFrame = ScreenshotCoordinateMapper.imageFrame(
        containerSize: proxy.size, imageSize: imageSize)

      ZStack(alignment: .topLeading) {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay {
            if interactionEnabled {
              RoundedRectangle(cornerRadius: 8)
                .stroke(.green, lineWidth: 3)
            }
          }
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        if interactionEnabled {
          PointerCaptureView(
            onClick: { point in
              guard
                let browserPoint = ScreenshotCoordinateMapper.browserPoint(
                  localPoint: CGPoint(x: point.x + imageFrame.minX, y: point.y + imageFrame.minY),
                  imageFrame: imageFrame,
                  imageSize: imageSize
                )
              else { return }
              onClick(browserPoint)
            },
            onScroll: { point, deltaX, deltaY in
              guard
                let browserPoint = ScreenshotCoordinateMapper.browserPoint(
                  localPoint: CGPoint(x: point.x + imageFrame.minX, y: point.y + imageFrame.minY),
                  imageFrame: imageFrame,
                  imageSize: imageSize
                )
              else { return }
              onScroll(browserPoint, deltaX, deltaY)
            },
            onKeyPress: { input in
              onKeyPress(input)
            }
          )
          .frame(width: imageFrame.width, height: imageFrame.height)
          .offset(x: imageFrame.minX, y: imageFrame.minY)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        interactionEnabled
          ? "Browser surface in control mode" : "Browser surface in view mode"
      )
      .accessibilityIdentifier("expanded-screenshot-surface")
    }
  }
}
