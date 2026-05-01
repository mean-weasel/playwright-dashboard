import AppKit
import Foundation
import SwiftData

@Model
final class SessionRecord {

  var sessionId: String  // e.g., "admin-ux-25c2"
  var customName: String?  // user-set label
  var autoLabel: String  // derived from worktree + URL
  var workspaceDir: String  // from .session file
  var workspaceName: String  // last path component of workspaceDir
  var projectName: String  // parent project (before .worktrees/ or .claude/worktrees/)
  var cdpPort: Int  // extracted from launch args
  var socketPath: String  // for playwright-cli communication
  var gridOrder: Int  // manual drag ordering
  var status: SessionStatus  // active/idle/stale/closed
  var lastScreenshot: Data?  // JPEG of last known state
  var lastURL: String?
  var lastTitle: String?
  var pageTargetsData: Data?
  var selectedTargetId: String?
  var createdAt: Date
  var closedAt: Date?  // nil if still open
  var lastActivityAt: Date  // for stale detection

  init(
    sessionId: String,
    autoLabel: String,
    workspaceDir: String,
    cdpPort: Int,
    socketPath: String,
    gridOrder: Int = 0,
    status: SessionStatus = .idle,
    customName: String? = nil,
    lastScreenshot: Data? = nil,
    lastURL: String? = nil,
    lastTitle: String? = nil,
    pageTargets: [CDPPageTarget] = [],
    selectedTargetId: String? = nil,
    createdAt: Date = Date(),
    closedAt: Date? = nil,
    lastActivityAt: Date = Date()
  ) {
    self.sessionId = sessionId
    self.customName = customName
    self.autoLabel = autoLabel
    self.workspaceDir = workspaceDir
    self.workspaceName = URL(fileURLWithPath: workspaceDir).lastPathComponent
    self.projectName = Self.extractProjectName(from: workspaceDir)
    self.cdpPort = cdpPort
    self.socketPath = socketPath
    self.gridOrder = gridOrder
    self.status = status
    self.lastScreenshot = lastScreenshot
    self.lastURL = lastURL
    self.lastTitle = lastTitle
    self.pageTargetsData = Self.encodePageTargets(pageTargets)
    self.selectedTargetId = selectedTargetId
    self.createdAt = createdAt
    self.closedAt = closedAt
    self.lastActivityAt = lastActivityAt
  }

  @Transient private var _cachedImage: NSImage?
  @Transient private var _cachedImageData: Data?

  /// Decoded NSImage from `lastScreenshot`, cached to avoid redundant JPEG decoding per render.
  var screenshotImage: NSImage? {
    if let _cachedImage, _cachedImageData == lastScreenshot {
      return _cachedImage
    }
    guard let data = lastScreenshot, let image = NSImage(data: data) else { return nil }
    _cachedImage = image
    _cachedImageData = data
    return image
  }

  /// Display name shown in UI, preferring user-set custom name over auto-generated label.
  var displayName: String {
    customName ?? autoLabel
  }

  var pageTargets: [CDPPageTarget] {
    get {
      guard let pageTargetsData else { return [] }
      return (try? JSONDecoder().decode([CDPPageTarget].self, from: pageTargetsData)) ?? []
    }
    set {
      pageTargetsData = Self.encodePageTargets(newValue)
      selectedTargetId = CDPPageTargetSelection.resolvedSelectedTargetId(
        currentSelectedTargetId: selectedTargetId,
        targets: newValue
      )
    }
  }

  var selectedPageTarget: CDPPageTarget? {
    CDPPageTargetSelection.selectedTarget(
      from: pageTargets,
      preferredTargetId: selectedTargetId
    )
  }

  func selectPageTarget(id: String?) {
    selectedTargetId = CDPPageTargetSelection.resolvedSelectedTargetId(
      currentSelectedTargetId: id,
      targets: pageTargets
    )
  }

  @discardableResult
  func updatePageTargets(_ targets: [CDPPageTarget]) -> Bool {
    let previousTargets = pageTargets
    let previousSelectedTargetId = selectedTargetId

    pageTargets = targets

    return previousTargets != pageTargets || previousSelectedTargetId != selectedTargetId
  }

  /// Whether the user explicitly closed this session (vs. auto-closed by sync when file disappeared).
  /// When true, the sync loop will not auto-reopen the session even if its file reappears.
  var userClosed: Bool = false

  /// Marks the session as closed with the current timestamp.
  /// Set `byUser: true` when the close was user-initiated (prevents sync from auto-reopening).
  func close(byUser: Bool = false) {
    status = .closed
    closedAt = Date()
    if byUser { userClosed = true }
  }

  /// Marks a user-requested close as in progress without hiding the live session yet.
  func beginClosing() {
    status = .closing
    closedAt = nil
  }

  /// Marks a failed close attempt while keeping the session visible for retry/recovery.
  func markCloseFailed() {
    status = .closeFailed
    closedAt = nil
    userClosed = false
  }

  /// Reopens a closed session, resetting it to idle.
  func reopen() {
    status = .idle
    closedAt = nil
    userClosed = false
  }

  /// Updates session fields from a CDP screenshot result.
  /// Centralizes status derivation so the logic isn't duplicated across services.
  func updateFromScreenshot(_ result: CDPClient.ScreenshotResult) {
    guard status != .closed else { return }

    let didChangeContent = result.url != lastURL || result.title != lastTitle
    lastScreenshot = result.jpeg
    lastURL = result.url
    lastTitle = result.title
    if !result.pageTargets.isEmpty {
      pageTargets = result.pageTargets
    }
    if let targetId = result.targetId {
      selectedTargetId = targetId
    }
    if didChangeContent {
      lastActivityAt = Date()
    }

    guard status != .closing && status != .closeFailed else { return }
    status = Self.deriveStatus(from: result.url)
  }

  /// Marks an active or idle session as stale when it has been inactive past `threshold`.
  @discardableResult
  func markStaleIfInactive(threshold: TimeInterval, now: Date = Date()) -> Bool {
    guard threshold > 0 else { return false }
    guard status == .active || status == .idle else { return false }

    let staleCutoff = now.addingTimeInterval(-threshold)
    guard lastActivityAt < staleCutoff else { return false }

    status = .stale
    return true
  }

  /// Derives session status from a page URL.
  /// Returns `.active` for real URLs, `.idle` for nil, empty, or about:blank.
  static func deriveStatus(from url: String?) -> SessionStatus {
    guard let url, !url.isEmpty, url != "about:blank" else { return .idle }
    return .active
  }

  /// Extracts the project/app name from a workspace directory path.
  /// Looks for `.claude/worktrees/` or `.worktrees/` markers and returns
  /// the directory before them. Falls back to the last path component.
  static func extractProjectName(from path: String) -> String {
    let markers = ["/.claude/worktrees/", "/.worktrees/"]
    for marker in markers {
      if let range = path.range(of: marker) {
        let projectPath = String(path[path.startIndex..<range.lowerBound])
        return URL(fileURLWithPath: projectPath).lastPathComponent
      }
    }
    return URL(fileURLWithPath: path).lastPathComponent
  }

  private static func encodePageTargets(_ targets: [CDPPageTarget]) -> Data? {
    guard !targets.isEmpty else { return nil }
    return try? JSONEncoder().encode(targets)
  }
}
