import AppKit
import Testing

@testable import PlaywrightDashboard

@Suite("BrowserKeyEventMapper")
struct BrowserKeyEventMapperTests {
  @Test("printable letter maps to CDP key input")
  func printableLetter() throws {
    let input = try #require(
      BrowserKeyEventMapper.keyEventInput(
        from: makeKeyEvent(characters: "a", charactersIgnoringModifiers: "a", keyCode: 0)))

    #expect(input.key == "a")
    #expect(input.code == "KeyA")
    #expect(input.text == "a")
    #expect(input.nativeVirtualKeyCode == 0)
    #expect(input.modifiers == 0)
    #expect(input.isPrintable)
  }

  @Test("shifted printable key preserves typed text and modifier")
  func shiftedPrintableKey() throws {
    let input = try #require(
      BrowserKeyEventMapper.keyEventInput(
        from: makeKeyEvent(
          characters: "A",
          charactersIgnoringModifiers: "a",
          modifierFlags: .shift,
          keyCode: 0
        )))

    #expect(input.key == "a")
    #expect(input.code == "KeyA")
    #expect(input.text == "A")
    #expect(input.modifiers == 8)
  }

  @Test("command modified key omits printable text")
  func commandModifiedKey() throws {
    let input = try #require(
      BrowserKeyEventMapper.keyEventInput(
        from: makeKeyEvent(
          characters: "s",
          charactersIgnoringModifiers: "s",
          modifierFlags: .command,
          keyCode: 1
        )))

    #expect(input.key == "s")
    #expect(input.code == "KeyS")
    #expect(input.text == nil)
    #expect(input.modifiers == 4)
  }

  @Test("special keys map to CDP names without printable text")
  func specialKeys() throws {
    let cases: [(UInt16, String, String?)] = [
      (36, "Enter", "Enter"),
      (48, "Tab", "Tab"),
      (51, "Backspace", "Backspace"),
      (53, "Escape", "Escape"),
      (123, "ArrowLeft", "ArrowLeft"),
      (124, "ArrowRight", "ArrowRight"),
      (125, "ArrowDown", "ArrowDown"),
      (126, "ArrowUp", "ArrowUp"),
    ]

    for (keyCode, key, code) in cases {
      let input = try #require(
        BrowserKeyEventMapper.keyEventInput(
          from: makeKeyEvent(
            characters: "\u{7F}",
            charactersIgnoringModifiers: key,
            keyCode: keyCode
          )
        ))

      #expect(input.key == key)
      #expect(input.code == code)
      #expect(input.text == nil)
      #expect(!input.isPrintable)
    }
  }

  private func makeKeyEvent(
    characters: String,
    charactersIgnoringModifiers: String,
    modifierFlags: NSEvent.ModifierFlags = [],
    keyCode: UInt16
  ) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifierFlags,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: charactersIgnoringModifiers,
      isARepeat: false,
      keyCode: keyCode
    )!
  }
}
