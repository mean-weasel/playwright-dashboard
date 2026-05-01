# Visual Snapshot QA

The visual snapshot harness captures deterministic dashboard screenshots from
the packaged macOS app. Pixel diffs are report-only by default so PR CI remains
stable, but an opt-in blocking mode can fail when a baseline is missing or a
snapshot changes beyond the configured threshold. Structural accessibility
assertions are always blocking for the captured state.

## Local

Prerequisite: grant Accessibility permission to every process identity macOS
attributes to the shell-driven AppleScript launch chain:

- the terminal or editor that launches the command, such as Terminal, iTerm,
  VS Code, Cursor, or Codex,
- the Node.js binary that runs the harness,
- `/usr/bin/osascript`,
- any wrapper or helper binary used to start the command.

Run the local probe before GUI QA:

```sh
make check-accessibility
```

The visual snapshot Make targets run the same probe before package validation
and before launching the app. If macOS denies access, the probe and snapshot
harness print the exact `process.execPath` for Node.js. Add or enable the
listed apps/binaries under System Settings > Privacy & Security >
Accessibility, then quit and reopen the terminal or editor before rerunning QA.
To add `/usr/bin/osascript`, use the file picker shortcut `Cmd+Shift+G`, enter
`/usr/bin/osascript`, and select it.

```sh
VISUAL_SNAPSHOT_DIR=dist/visual-snapshots make visual-snapshots
```

For the CI-gated structural smoke subset, run:

```sh
make visual-structure-smoke
```

The harness launches `dist/PlaywrightDashboard.app` with smoke-only arguments, points it at an isolated temporary daemon directory, uses an in-memory SwiftData store, and writes PNGs to `dist/visual-snapshots`.
Dashboard and settings snapshots disable background screenshot refresh so the
fixtures do not mutate while the capture is running.

Before each PNG is captured, the harness reads the app's accessibility tree and
asserts expected structural markers:

- `empty-dashboard`: `session-empty-state`, `No Active Sessions`, and zero
  `session-card-*` identifiers.
- `populated-dashboard`: four seeded `session-card-*` identifiers and their
  visible session names.
- `settings`: `settings-view` and `Launch at login`.
- `closed-history`: the closed session card and exactly one `session-card-*`
  identifier after the backing daemon directory is removed.
- `expanded-session`: the screenshot surface, expanded toolbar controls, the
  metadata toggle, the session title, and `Live screencast`.

`make visual-structure-smoke` uses the same assertions in structure-only mode
for `empty-dashboard`, `populated-dashboard`, `settings`, and `closed-history`.
It does not capture PNGs, compare pixels, or start the Chrome-backed expanded
session fixture. The output directory is `dist/visual-structure-smoke`.

Current snapshots:

- `empty-dashboard.png`
- `populated-dashboard.png`
- `settings.png`
- `closed-history.png`
- `expanded-session.png`

The harness also writes `manifest.json` with the generated timestamp, app path,
snapshot filenames, pixel dimensions, byte sizes, SHA-256 hashes, and
artifact-only mode. It also writes `summary.md`, a local copy of the same table
CI adds to the job summary.
Each case also writes `<snapshot-name>-structure.txt` with the assertions and
the observed accessibility names/identifiers. On failure, the harness writes
`<snapshot-name>-error.txt` and `<snapshot-name>-ui-snapshot.txt`.

To compare against a local baseline directory without failing the run:

```sh
make visual-snapshot-baseline
make visual-snapshot-compare
```

When a baseline is configured, `manifest.json` and `summary.md` report each
snapshot as `unchanged`, `changed-within-threshold`,
`changed-over-threshold`, `dimension-mismatch`, or `missing`. The manifest
includes the pixel mismatch ratio, threshold, per-channel pixel threshold,
dimension data, and byte delta for changed snapshots. Baseline changes are
non-blocking unless visual diff enforcement is enabled.
Expect exact PNG hashes to be sensitive to macOS window rendering, shadows, and
live browser content. Use baseline status as a review signal, not as proof of a
behavioral regression.

Override the default directories with `VISUAL_SNAPSHOT_BASELINE_DIR` and
`VISUAL_SNAPSHOT_COMPARE_DIR` when comparing against a saved artifact set.

To opt into blocking visual diffs:

```sh
make visual-snapshot-enforce
```

`visual-snapshot-enforce` requires `VISUAL_SNAPSHOT_BASELINE_DIR` to exist and
writes comparison artifacts to `VISUAL_SNAPSHOT_COMPARE_DIR`. It fails after
writing `manifest.json` and `summary.md` when any configured baseline PNG is
missing, dimensions differ, or the mismatch ratio is greater than
`VISUAL_SNAPSHOT_DIFF_THRESHOLD`. The default threshold is `0.01` (1% of
pixels), with `VISUAL_SNAPSHOT_PIXEL_THRESHOLD=2` allowing small per-channel
anti-aliasing differences before a pixel counts as changed.

Use blocking mode for deliberate baseline review, release hardening, or a
branch whose baseline artifact is pinned to the same macOS/Xcode runner image.
Do not add it to the default PR gate until runner rendering drift has been
measured and the baseline update process is explicit.

## CI

The main `CI` workflow runs `visual-structure-smoke` after package validation
on normal CI paths and includes it in the `CI Gate` job. A missing structural
marker fails CI; PNG hashes and visual diffs are not part of this required
gate. The job uploads `dist/visual-structure-smoke/**` as the
`visual-structure-smoke` artifact.

The fuller `visual-snapshots` job still runs only on scheduled and manually
dispatched CI, then uploads `dist/visual-snapshots/**` as the
`visual-snapshots` artifact. Keep pixel output report-only in required PR CI.
For an opt-in blocking CI path, provide a baseline directory or downloaded
baseline artifact, then run:

```sh
VISUAL_SNAPSHOT_BASELINE_DIR=path/to/baseline \
VISUAL_SNAPSHOT_COMPARE_DIR=dist/visual-snapshots \
VISUAL_SNAPSHOT_DIFF_THRESHOLD=0.01 \
VISUAL_SNAPSHOT_PIXEL_THRESHOLD=2 \
make visual-snapshot-enforce
```
