import SwiftData
import Foundation

@Model
final class SessionRecord {

    var sessionId: String          // e.g., "admin-ux-25c2"
    var customName: String?        // user-set label
    var autoLabel: String          // derived from worktree + URL
    var workspaceDir: String       // from .session file
    var workspaceName: String      // last path component of workspaceDir
    var projectName: String        // parent project (before .worktrees/ or .claude/worktrees/)
    var cdpPort: Int               // extracted from launch args
    var socketPath: String         // for playwright-cli communication
    var gridOrder: Int             // manual drag ordering
    var status: SessionStatus      // active/idle/stale/closed
    var lastScreenshot: Data?      // JPEG of last known state
    var lastURL: String?
    var lastTitle: String?
    var createdAt: Date
    var closedAt: Date?            // nil if still open
    var lastActivityAt: Date       // for stale detection

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
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.lastActivityAt = lastActivityAt
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
}
