import Foundation

extension CDPClient {
  static func commandString(id: Int, method: String, params: [String: Any]) throws -> String {
    let command: [String: Any] = ["id": id, "method": method, "params": params]
    let data = try JSONSerialization.data(withJSONObject: command, options: [.sortedKeys])
    guard let string = String(data: data, encoding: .utf8) else {
      throw CDPError.invalidResponse
    }
    return string
  }

  static func mouseEventParams(
    type: String,
    x: Double,
    y: Double,
    button: String,
    clickCount: Int
  ) -> [String: Any] {
    [
      "type": type,
      "x": x,
      "y": y,
      "button": button,
      "clickCount": clickCount,
    ]
  }

  static func mouseWheelParams(
    x: Double,
    y: Double,
    deltaX: Double,
    deltaY: Double
  ) -> [String: Any] {
    [
      "type": "mouseWheel",
      "x": x,
      "y": y,
      "button": "none",
      "deltaX": deltaX,
      "deltaY": deltaY,
    ]
  }

  struct KeyEventInput: Sendable {
    let key: String
    let code: String?
    let text: String?
    let nativeVirtualKeyCode: Int
    let modifiers: Int

    var isPrintable: Bool {
      guard let text else { return false }
      return !text.isEmpty
        && text.unicodeScalars.allSatisfy {
          !CharacterSet.controlCharacters.contains($0)
        }
    }
  }

  static func keyEventParams(
    type: String,
    input: KeyEventInput,
    includeText: Bool
  ) -> [String: Any] {
    var params: [String: Any] = [
      "type": type,
      "key": input.key,
      "windowsVirtualKeyCode": input.nativeVirtualKeyCode,
      "nativeVirtualKeyCode": input.nativeVirtualKeyCode,
      "modifiers": input.modifiers,
    ]
    if let code = input.code {
      params["code"] = code
    }
    if includeText, let text = input.text {
      params["text"] = text
      params["unmodifiedText"] = text
    }
    return params
  }

  static func pageForScreenshot(from pages: [PageInfo]) -> PageInfo? {
    let debuggablePages = pages.filter { page in
      page.type == "page"
        && page.webSocketDebuggerUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          == false
    }

    return debuggablePages.first(where: { page in
      guard page.type == "page",
        let url = page.url?.trimmingCharacters(in: .whitespacesAndNewlines)
      else {
        return false
      }
      return !url.isEmpty && url != "about:blank"
    }) ?? debuggablePages.first
  }

  static func isCommandResponse(_ text: String, expectedId: Int) throws -> Bool {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let responseId = json["id"] as? Int,
      responseId == expectedId
    else {
      return false
    }

    if let error = json["error"] as? [String: Any] {
      let message = error["message"] as? String ?? "Unknown CDP error"
      throw CDPError.protocolError(message)
    }

    return true
  }
}
