# Visual Snapshot QA

The visual snapshot harness captures deterministic dashboard screenshots from the packaged macOS app. It is artifact-only: it does not compare images or fail on visual diffs yet.

## Local

```sh
VISUAL_SNAPSHOT_DIR=dist/visual-snapshots make visual-snapshots
```

The harness launches `dist/PlaywrightDashboard.app` with smoke-only arguments, points it at an isolated temporary daemon directory, uses an in-memory SwiftData store, and writes PNGs to `dist/visual-snapshots`.
Dashboard and settings snapshots disable background screenshot refresh so the
fixtures do not mutate while the capture is running.

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

To compare against a local baseline directory without failing the run:

```sh
make visual-snapshot-baseline
make visual-snapshot-compare
```

When a baseline is configured, `manifest.json` and `summary.md` report each
snapshot as `unchanged`, `changed`, or `missing`. This is intentionally
non-blocking until runner rendering is stable enough for visual diff thresholds.
Expect exact PNG hashes to be sensitive to macOS window rendering, shadows, and
live browser content. Use baseline status as a review signal, not as proof of a
behavioral regression.

Override the default directories with `VISUAL_SNAPSHOT_BASELINE_DIR` and
`VISUAL_SNAPSHOT_COMPARE_DIR` when comparing against a saved artifact set.

## CI

The main `CI` workflow runs visual snapshots on scheduled and manual runs after package validation, then uploads `dist/visual-snapshots/**` as the `visual-snapshots` artifact.

PR CI does not run this job yet. Keep it artifact-only until macOS runner rendering is proven stable enough for image diff thresholds.
