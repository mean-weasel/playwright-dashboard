import AppKit

enum BrowserKeyEventMapper {
  static func keyEventInput(from event: NSEvent) -> CDPClient.KeyEventInput? {
    let key = event.charactersIgnoringModifiers ?? event.characters ?? ""
    guard !key.isEmpty else { return nil }
    return CDPClient.KeyEventInput(
      key: keyName(for: event.keyCode, fallback: key),
      code: codeName(for: event.keyCode),
      text: printableText(from: event),
      nativeVirtualKeyCode: Int(event.keyCode),
      modifiers: cdpModifiers(from: event.modifierFlags)
    )
  }

  private static func printableText(from event: NSEvent) -> String? {
    if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false {
      return nil
    }
    guard let text = event.characters, text.count == 1,
      text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else {
      return nil
    }
    return text
  }

  private static func cdpModifiers(from flags: NSEvent.ModifierFlags) -> Int {
    var modifiers = 0
    if flags.contains(.option) { modifiers |= 1 }
    if flags.contains(.control) { modifiers |= 2 }
    if flags.contains(.command) { modifiers |= 4 }
    if flags.contains(.shift) { modifiers |= 8 }
    return modifiers
  }

  private static func keyName(for keyCode: UInt16, fallback: String) -> String {
    switch keyCode {
    case 36: return "Enter"
    case 48: return "Tab"
    case 49: return " "
    case 51: return "Backspace"
    case 53: return "Escape"
    case 123: return "ArrowLeft"
    case 124: return "ArrowRight"
    case 125: return "ArrowDown"
    case 126: return "ArrowUp"
    default: return fallback
    }
  }

  private static func codeName(for keyCode: UInt16) -> String? {
    switch keyCode {
    case 0: return "KeyA"
    case 1: return "KeyS"
    case 2: return "KeyD"
    case 3: return "KeyF"
    case 4: return "KeyH"
    case 5: return "KeyG"
    case 6: return "KeyZ"
    case 7: return "KeyX"
    case 8: return "KeyC"
    case 9: return "KeyV"
    case 11: return "KeyB"
    case 12: return "KeyQ"
    case 13: return "KeyW"
    case 14: return "KeyE"
    case 15: return "KeyR"
    case 16: return "KeyY"
    case 17: return "KeyT"
    case 31: return "KeyO"
    case 32: return "KeyU"
    case 34: return "KeyI"
    case 35: return "KeyP"
    case 37: return "KeyL"
    case 38: return "KeyJ"
    case 40: return "KeyK"
    case 45: return "KeyN"
    case 46: return "KeyM"
    case 18: return "Digit1"
    case 19: return "Digit2"
    case 20: return "Digit3"
    case 21: return "Digit4"
    case 23: return "Digit5"
    case 22: return "Digit6"
    case 26: return "Digit7"
    case 28: return "Digit8"
    case 25: return "Digit9"
    case 29: return "Digit0"
    case 36: return "Enter"
    case 48: return "Tab"
    case 49: return "Space"
    case 51: return "Backspace"
    case 53: return "Escape"
    case 123: return "ArrowLeft"
    case 124: return "ArrowRight"
    case 125: return "ArrowDown"
    case 126: return "ArrowUp"
    default: return nil
    }
  }
}
