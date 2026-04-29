import AppKit
import SwiftUI

struct PointerCaptureView: NSViewRepresentable {
  let onClick: (CGPoint) -> Void
  let onScroll: (CGPoint, CGFloat, CGFloat) -> Void

  func makeNSView(context: Context) -> CaptureNSView {
    let view = CaptureNSView()
    view.onClick = onClick
    view.onScroll = onScroll
    return view
  }

  func updateNSView(_ nsView: CaptureNSView, context: Context) {
    nsView.onClick = onClick
    nsView.onScroll = onScroll
  }

  final class CaptureNSView: NSView {
    var onClick: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, CGFloat, CGFloat) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
      window?.makeFirstResponder(self)
      onClick?(convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
      onScroll?(
        convert(event.locationInWindow, from: nil), event.scrollingDeltaX, event.scrollingDeltaY)
    }
  }
}
