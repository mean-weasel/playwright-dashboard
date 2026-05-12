# Playwright Dashboard — User Guide

Playwright Dashboard is a macOS menu bar app that discovers and observes
local `playwright-cli` browser sessions. This guide covers what the app
does, the safety boundaries between Safe and Control mode, common
workflows, and how to recover when things go sideways.

For install instructions and beta-feedback steps, see
[`BETA_TESTING.md`](../BETA_TESTING.md). For the no-telemetry stance, see
[`telemetry-policy.md`](telemetry-policy.md). For development workflows,
see [`development.md`](development.md).

## What the app does

The app watches `~/Library/Caches/ms-playwright/daemon` for `*.session`
files that `playwright-cli` writes whenever a browser session is opened.
When a new session appears, the app shows it in two places:

- The **menu bar popover** (the dropdown that opens when you click the
  app's icon in the macOS menu bar) gives a compact list of active
  sessions plus a one-click way to open the full dashboard, check for
  updates, or quit.
- The **dashboard window** shows all sessions as cards, with a sidebar
  filter (all open, idle/stale, closed, by workspace), a search box, and
  an expanded session view per session that includes the live screencast,
  metadata, recording controls, and tab/target picker.

Sessions you open with `playwright-cli ... open --browser=chrome --headed`
are picked up automatically — there is no separate sign-in or sync.

## Safe mode vs. Control mode

Safe mode is **on by default** for new installs. It defines the line
between observing a session and acting on it.

### Safe mode (read-only — the default)

The dashboard is allowed to:

- Discover sessions and read their `.session` metadata.
- Show thumbnails and live screencast frames.
- Save screenshots to `~/Downloads`.
- Capture, review, and export recordings.
- Show CDP target info (URL, title, tab list) for the selected target.
- Export diagnostics for support.

The dashboard is **blocked** from:

- Closing sessions or running stale-cleanup.
- Opening the CDP inspector for a session.
- Navigating the browser to a new URL.
- Forwarding pointer / scroll / keyboard input through to the page.

Safe mode is the right default for observing a running test or someone
else's session — you can look at everything, but nothing the dashboard
does will perturb the page.

### Control mode (per-session opt-in)

Each session can be promoted out of Safe mode individually:

1. Open the session in the **expanded view** (click a card in the
   dashboard).
2. Click **Enable browser control** in the toolbar.
3. Confirm the prompt.

That session now allows navigation, CDP inspector access, and forwarded
input — but **only that session**. Other sessions stay in Safe mode.
There is a **Return to Safe Mode** button in the toolbar that revokes the
authorization for that session at any time.

Global Safe mode (in **Settings → Safety**) is a separate switch — if you
turn that off, *every* session opens in Control mode by default. Most
users should leave global Safe mode on and opt in per session.

## Common workflows

### Watch a session a test is driving

1. Run your `playwright-cli` test in headed mode.
2. The session appears as a card. Click it.
3. The expanded view shows the live screencast at ~10 fps. Frames pause
   when the page is idle and resume when the page paints.

You're in Safe mode by default — nothing in the dashboard can touch the
page.

### Drive a one-off session yourself

1. Open the session and click the card to enter the expanded view.
2. Click **Enable browser control** and confirm.
3. Use the URL bar to navigate. Click and type in the screencast surface
   to send pointer / keyboard input to the page.
4. When you're done, click **Return to Safe Mode** (or close the session
   via `playwright-cli ... close`).

### Reorder, rename, search, filter

- **Rename** a session: right-click its card, choose Rename, and type a
  new name. The custom name persists across app restarts.
- **Reorder** sessions: drag a card to a new position in the grid. Order
  persists.
- **Filter** by status using the sidebar (All open, Idle/Stale, Closed,
  or a specific workspace).
- **Search** with `Cmd+F` to filter the grid by name or URL.
- **Closed history**: pick the **Closed** filter in the sidebar to see
  sessions that have ended. They are kept until you clear them.

### Record and export an MP4

1. Open the session in expanded view, enable Control mode.
2. Click the **Record** button in the toolbar. Frames are written to
   `~/Downloads/PlaywrightDashboard Recordings/<session-name>/`.
3. Click **Stop**. The app exports an MP4 next to the frame files.

The folder and film icons in the toolbar open the recording directory and
play the MP4 in the system player.

### Multi-tab / target switching

If a session has more than one open tab, the expanded view's metadata
panel includes a target picker. Switching the selected target switches
the screencast, URL, and title to that tab. Closing the inactive tab via
the browser does not break the active one.

## Troubleshooting

### "I started a session and the dashboard doesn't see it"

- Confirm `playwright-cli` actually wrote a `.session` file under
  `~/Library/Caches/ms-playwright/daemon/<hash>/`. If not, the CLI
  failed before the daemon spawned.
- Re-open the dashboard from the menu bar — the watcher does an initial
  scan on launch in case FSEvents missed something.
- Check that the session's `socketPath` (in the `.session` JSON) and the
  app's daemon dir agree. Smoke tests use an override
  (`--smoke-daemon-dir`) — regular use should leave this alone.

### "Screencast is frozen"

- The connection state badge in the expanded toolbar shows one of
  **Waiting**, **Live**, **Snapshots**, or **Disconnected**. **Live** is
  CDP screencast events streaming. **Snapshots** means the dashboard
  fell back to polling (still works, just lower fps). **Disconnected**
  means the CDP refresh is failing.
- If the badge sticks at **Disconnected**, the underlying Chrome may
  have died. Close the session and reopen.
- Sleep/wake on a laptop sometimes causes a brief **Disconnected** —
  the dashboard reconnects automatically within ~10–30 s.

### "A session shows as Stale and won't go away"

Stale sessions are sessions that have been idle past the configured
threshold (default 2 minutes — see **Settings → Sessions**). Options:

- Switch to **Control mode** and click **Close** on the card.
- Run **Clean up stale** from the sidebar (also Control mode).
- Run `playwright-cli -s=<name> close` from the terminal.

### "Close failed" on a session

The dashboard tried to run `playwright-cli close` and the daemon returned
an error. Common causes:

- `playwright-cli` is not on `PATH` for the app's environment.
- The daemon was already gone (Chrome crashed). The card will show a
  **Close failed** badge — dismiss it from the card menu and the
  session will transition to closed once the watcher confirms the
  `.session` file is gone.

### "Chrome crashed mid-session"

The dashboard notices when the Chrome process for a session dies and
transitions the card to **Closed**. No action needed — just open a new
session if you still need one.

### "Where are my recordings?"

`~/Downloads/PlaywrightDashboard Recordings/<session-name>/`. Each
session gets its own folder with `manifest.json`, numbered JPEG frames,
and a `recording.mp4`. The folder icon in the recording toolbar opens
that directory in Finder.

## Privacy and what data leaves the app

The short version: **no data leaves your machine unless you export it
manually**. See [`telemetry-policy.md`](telemetry-policy.md) for the
full statement. The **Check for Updates** menu item opens the GitHub
Releases page in your default browser — the request comes from the
browser, not the app.

To share information about an issue, use **Settings → Diagnostics →
Export Diagnostics**, review the file (it excludes screenshots,
cookies, page content, and recordings), and attach it to a GitHub
issue.

## Checking for updates

The menu bar popover has an **arrow-down** button next to the dashboard
and quit buttons. Click it to open
[github.com/mean-weasel/playwright-dashboard/releases/latest][releases]
in your browser. There is no in-app auto-installer; download the latest
notarized zip, unzip it, and replace the existing
`PlaywrightDashboard.app`.

[releases]: https://github.com/mean-weasel/playwright-dashboard/releases/latest
