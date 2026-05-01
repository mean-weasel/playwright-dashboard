import Foundation

extension CDPClient {
  enum NavigationError: Error, LocalizedError, Equatable {
    case emptyURL
    case invalidURL
    case unsupportedScheme(String)
    case navigationFailed(String)

    var errorDescription: String? {
      switch self {
      case .emptyURL:
        return "Enter a URL to navigate."
      case .invalidURL:
        return "Enter a valid HTTP or HTTPS URL."
      case .unsupportedScheme(let scheme):
        return "Only HTTP and HTTPS URLs can be opened. \(scheme) is not supported."
      case .navigationFailed(let message):
        return "Navigation failed: \(message)"
      }
    }
  }

  static func commandString(id: Int, method: String, params: [String: Any]) throws -> String {
    let command: [String: Any] = ["id": id, "method": method, "params": params]
    let data = try JSONSerialization.data(withJSONObject: command, options: [.sortedKeys])
    guard let string = String(data: data, encoding: .utf8) else {
      throw CDPError.invalidResponse
    }
    return string
  }

  static func normalizedNavigationURLString(_ rawValue: String) throws -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw NavigationError.emptyURL
    }

    let valueWithScheme: String
    if trimmed.contains("://") {
      valueWithScheme = trimmed
    } else if Self.looksLikeUnsupportedScheme(trimmed) {
      let scheme = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
      throw NavigationError.unsupportedScheme(scheme)
    } else {
      valueWithScheme = "https://\(trimmed)"
    }

    guard var components = URLComponents(string: valueWithScheme),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme)
    else {
      let scheme = URLComponents(string: valueWithScheme)?.scheme ?? "unknown"
      throw NavigationError.unsupportedScheme(scheme)
    }

    components.scheme = scheme
    guard components.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
      let url = components.url
    else {
      throw NavigationError.invalidURL
    }

    return url.absoluteString
  }

  static func pageNavigateParams(url: String) -> [String: Any] {
    ["url": url]
  }

  static func pageNavigateErrorText(from text: String) -> String? {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = json["result"] as? [String: Any],
      let errorText = result["errorText"] as? String,
      !errorText.isEmpty
    else {
      return nil
    }
    return errorText
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
    guard
      let target = CDPPageTargetSelection.selectedTarget(
        from: pages,
        preferredTargetId: nil
      )
    else {
      return nil
    }
    return pages.first { $0.id == target.id }
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

  private static func looksLikeUnsupportedScheme(_ value: String) -> Bool {
    guard let colonIndex = value.firstIndex(of: ":") else { return false }
    let prefix = value[..<colonIndex]
    guard
      prefix.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*$"#, options: .regularExpression)
        != nil
    else {
      return false
    }

    let suffix = value[value.index(after: colonIndex)...]
    let pathStart = suffix.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
    let portCandidate = pathStart.map { suffix[..<$0] } ?? suffix[...]
    return portCandidate.isEmpty
      || portCandidate.range(of: #"^[0-9]+$"#, options: .regularExpression) == nil
  }
}
