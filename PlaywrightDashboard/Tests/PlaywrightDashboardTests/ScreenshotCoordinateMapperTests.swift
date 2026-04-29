import Foundation
import Testing

@testable import PlaywrightDashboard

@Suite("ScreenshotCoordinateMapper")
struct ScreenshotCoordinateMapperTests {

  @Test("imageFrame fits image inside wide container")
  func imageFrameWideContainer() {
    let frame = ScreenshotCoordinateMapper.imageFrame(
      containerSize: CGSize(width: 1000, height: 600),
      imageSize: CGSize(width: 800, height: 600)
    )

    #expect(frame == CGRect(x: 100, y: 0, width: 800, height: 600))
  }

  @Test("imageFrame fits image inside tall container")
  func imageFrameTallContainer() {
    let frame = ScreenshotCoordinateMapper.imageFrame(
      containerSize: CGSize(width: 800, height: 800),
      imageSize: CGSize(width: 800, height: 400)
    )

    #expect(frame == CGRect(x: 0, y: 200, width: 800, height: 400))
  }

  @Test("browserPoint maps container point to image pixels")
  func browserPointMapping() throws {
    let point = try #require(
      ScreenshotCoordinateMapper.browserPoint(
        localPoint: CGPoint(x: 500, y: 300),
        imageFrame: CGRect(x: 100, y: 0, width: 800, height: 600),
        imageSize: CGSize(width: 1600, height: 1200)
      ))

    #expect(point == CGPoint(x: 800, y: 600))
  }

  @Test("browserPoint rejects points outside image")
  func browserPointOutsideImage() {
    let point = ScreenshotCoordinateMapper.browserPoint(
      localPoint: CGPoint(x: 50, y: 300),
      imageFrame: CGRect(x: 100, y: 0, width: 800, height: 600),
      imageSize: CGSize(width: 1600, height: 1200)
    )

    #expect(point == nil)
  }
}
