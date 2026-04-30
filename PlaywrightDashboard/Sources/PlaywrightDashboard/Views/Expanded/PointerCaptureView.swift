import AppKit
import SwiftUI

struct PointerCaptureView: NSViewRepresentable {
  let onClick: (CGPoint) -> Void
  let onScroll: (CGPoint, CGFloat, CGFloat) -> Void
  let onKeyPress: (CDPClient.KeyEventInput) -> Void

  func makeNSView(context: Context) -> CaptureNSView {
    let view = CaptureNSView()
    view.onClick = onClick
    view.onScroll = onScroll
    view.onKeyPress = onKeyPress
    return view
  }

  func updateNSView(_ nsView: CaptureNSView, context: Context) {
    nsView.onClick = onClick
    nsView.onScroll = onScroll
    nsView.onKeyPress = onKeyPress
  }

  final class CaptureNSView: NSView {
    var onClick: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, CGFloat, CGFloat) -> Void)?
    var onKeyPress: ((CDPClient.KeyEventInput) -> Void)?

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

    override func keyDown(with event: NSEvent) {
      guard let input = BrowserKeyEventMapper.keyEventInput(from: event) else {
        super.keyDown(with: event)
        return
      }
      onKeyPress?(input)
    }
  }
}
