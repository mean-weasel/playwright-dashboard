import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export const cases = [
  {
    name: "empty-dashboard",
    window: "dashboard",
    expectedElement: "session-empty-state",
    sessions: [],
  },
  {
    name: "populated-dashboard",
    window: "dashboard",
    expectedElement: "session-card-visual-active",
    sessions: [
      sessionFixture("visual-active", "Visual Active", "dashboard", 9222),
      sessionFixture("visual-idle", "Visual Idle", "idle-worktree", 0),
      sessionFixture("visual-stale", "Visual Stale", "stale-worktree", 0),
      sessionFixture("visual-review", "Visual Review", "review-worktree", 0),
    ],
  },
  {
    name: "settings",
    window: "settings",
    expectedElement: "settings-view",
    sessions: [],
  },
  {
    name: "closed-history",
    window: "dashboard",
    expectedElement: null,
    finalExpectedElement: "session-card-visual-closed",
    afterLaunch: "closed-history",
    dashboardFilter: "closed",
    sessions: [
      sessionFixture("visual-closed", "Visual Closed", "closed-worktree", 0),
    ],
  },
  {
    name: "expanded-session",
    window: "expanded",
    expectedElement: "expanded-screenshot-surface",
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
