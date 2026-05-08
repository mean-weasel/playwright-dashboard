import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export const cases = [
  {
    name: "empty-dashboard",
    window: "dashboard",
    expectedElement: "session-empty-state",
    assertions: {
      identifiers: ["session-empty-state", "session-empty-state-title"],
      identifierPrefixes: {
        "session-card-": 0,
      },
    },
    sessions: [],
  },
  {
    name: "populated-dashboard",
    window: "dashboard",
    expectedElement: "session-card-visual-active",
    assertions: {
      identifiers: [
        "session-card-visual-active",
        "session-card-visual-idle",
        "session-card-visual-stale",
        "session-card-visual-review",
      ],
      identifierPrefixes: {
        "session-card-visual-": 4,
      },
    },
    sessions: [
      sessionFixture("visual-active", "Visual Active", "dashboard", 9222),
      sessionFixture("visual-idle", "Visual Idle", "idle-worktree", 0),
      sessionFixture("visual-stale", "Visual Stale", "stale-worktree", 0),
      sessionFixture("visual-review", "Visual Review", "review-worktree", 0),
    ],
  },
  {
    name: "safe-mode-dashboard",
    window: "dashboard",
    expectedElement: "safe-mode-badge",
    safeMode: true,
    assertions: {
      identifiers: [
        "safe-mode-badge",
        "sidebar-safe-mode-badge",
        "session-card-thumbnail-state-visual-safe-active",
        "session-card-thumbnail-state-visual-safe-stale",
        "session-card-visual-safe-stale",
      ],
      names: ["Safe"],
      identifierPrefixes: {
        "session-card-visual-safe-": 2,
      },
    },
    sessions: [
      sessionFixture("visual-safe-active", "Visual Safe Active", "safe-active", 9222),
      sessionFixture("visual-safe-stale", "Visual Safe Stale", "safe-stale", 0),
    ],
  },
  {
    name: "settings",
    window: "settings",
    expectedElement: "settings-view",
    assertions: {
      identifiers: ["settings-view"],
      names: ["Launch at login"],
    },
    sessions: [],
  },
  {
    name: "closed-history",
    window: "dashboard",
    expectedElement: null,
    finalExpectedElement: "session-card-visual-closed",
    afterLaunch: "closed-history",
    dashboardFilter: "closed",
    assertions: {
      identifiers: ["session-card-visual-closed"],
      identifierPrefixes: {
        "session-card-visual-": 1,
      },
    },
    sessions: [
      sessionFixture("visual-closed", "Visual Closed", "closed-worktree", 0),
    ],
  },
  {
    name: "expanded-session",
    window: "expanded",
    expectedElement: "expanded-screenshot-surface",
    assertions: {
      identifiers: [
        "expanded-screenshot-surface",
        "expanded-connection-summary",
        "expanded-save-screenshot",
        "expanded-open-current-url",
        "expanded-open-cdp-inspector",
        "expanded-interaction-mode",
        "expanded-metadata-toggle",
      ],
      names: ["Visual Expanded", "Live"],
    },
  },
];

export async function seedSessions(daemonDir, sessions) {
  await mkdir(daemonDir, { recursive: true });
  for (const session of sessions) {
    const sessionDir = path.join(daemonDir, session.workspaceHash);
    await mkdir(sessionDir, { recursive: true });
    await writeFile(
      path.join(sessionDir, `${session.name}.session`),
      `${JSON.stringify(session.payload)}\n`,
      "utf8",
    );
  }
}

export function sessionFixture(name, label, worktreeName, cdpPort) {
  const workspaceDir = path.join(
    os.tmpdir(),
    "playwright-dashboard-visual-fixtures",
    "PlaywrightDashboard",
    ".worktrees",
    worktreeName,
  );
  return {
    name,
    workspaceHash: `hash-${name}`,
    payload: {
      name,
      version: "1",
      timestamp: Date.now(),
      socketPath: path.join(os.tmpdir(), `${name}.sock`),
      workspaceDir,
      cli: {},
      browser: {
        browserName: "chromium",
        launchOptions: {
          headless: false,
          chromiumSandbox: false,
          args: cdpPort > 0 ? [`--remote-debugging-port=${cdpPort}`] : [],
        },
      },
      label,
    },
  };
}
