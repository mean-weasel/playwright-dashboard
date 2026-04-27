import Foundation

struct AutoLabeler {

  // Common abbreviations that should be fully uppercased
  private static let abbreviations: Set<String> = [
    "ux", "ui", "qa", "api", "ci", "cd", "pr", "db", "css", "html", "sdk", "cli",
  ]

  /// Returns the best human-readable label for a session and updates `record.autoLabel`.
  @discardableResult
  static func label(for record: SessionRecord) -> String {
    let result: String

    // Priority 1: user-set custom name
    if let custom = record.customName, !custom.isEmpty {
      result = custom
    }
    // Priority 2: workspace/worktree branch name
    else if !record.workspaceName.isEmpty {
      let titled = titleCase(workspaceName: record.workspaceName)
      if !titled.isEmpty {
        result = titled
      } else {
        result = fallback(for: record)
      }
    }
    // Priority 3 & 4: lastTitle or sessionId
    else {
      result = fallback(for: record)
    }

    record.autoLabel = result
    return result
  }

  /// Converts a workspace/worktree name into a human-readable title.
  /// Exposed for unit testing.
  static func titleCase(workspaceName: String) -> String {
    // Replace hyphens and underscores with spaces
    let name =
      workspaceName
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")

    // Split into words
    var words = name.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

    // Strip trailing short hex hash suffix (4-8 hex chars) from the last word
    if let last = words.last, isHexHash(last) && words.count > 1 {
      words.removeLast()
    }

    if words.isEmpty {
      return ""
    }

    // Capitalize each word, uppercasing known abbreviations
    let capitalizedWords = words.map { word -> String in
      let lower = word.lowercased()
      if abbreviations.contains(lower) {
        return lower.uppercased()
      }
      return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }

    return capitalizedWords.joined(separator: " ")
  }

  // MARK: - Private helpers

  private static func fallback(for record: SessionRecord) -> String {
    if let title = record.lastTitle, !title.isEmpty {
      return title
    }
    return record.sessionId
  }

  /// Returns true if the string is 4-8 hexadecimal characters (hash suffix pattern).
  private static func isHexHash(_ s: String) -> Bool {
    let len = s.count
    guard len >= 4 && len <= 8 else { return false }
    return s.allSatisfy { $0.isHexDigit }
  }
}
