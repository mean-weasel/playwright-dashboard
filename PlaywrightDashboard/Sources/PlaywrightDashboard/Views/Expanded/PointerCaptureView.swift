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
    nsView.preserveKeyboardCaptureIfPossible()
  }

  final class CaptureNSView: NSView {
    var onClick: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, CGFloat, CGFloat) -> Void)?
    var onKeyPress: ((CDPClient.KeyEventInput) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      wantsLayer = true
      layer?.backgroundColor = NSColor.clear.cgColor
    }

    // point is in superview coordinates; use frame (not bounds) for the containment check.
    override func hitTest(_ point: NSPoint) -> NSView? {
      guard !isHidden, alphaValue > 0, frame.contains(point) else { return nil }
      return self
    }

    // Allow the first click on an inactive window to register as a real click
    // rather than merely activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      preserveKeyboardCaptureIfPossible()
    }

    override func mouseDown(with event: NSEvent) {
      becomeKeyboardCaptureIfPossible()
      onClick?(convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
      becomeKeyboardCaptureIfPossible()
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

    func becomeKeyboardCaptureIfPossible() {
      guard let window, window.firstResponder !== self else { return }
      window.makeFirstResponder(self)
    }

    func preserveKeyboardCaptureIfPossible() {
      guard let window else { return }
      guard !(window.firstResponder is NSTextView) else { return }
      becomeKeyboardCaptureIfPossible()
    }
  }
}
