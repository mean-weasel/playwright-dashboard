# Top Improvements Plan

## Goal

Move Playwright Dashboard from a credible MVP toward a trustworthy daily-use tool. The priority is to close the gap between the product promise and the implemented behavior, then add QA gates that catch regressions in the real user flows.

## Phase 1: Product-Honest UX

- Replace generic empty states with setup-aware states for no sessions, no search results, closed history, idle/stale filters, and workspace filters.
- Make the expanded view explicit that it is currently a refreshed CDP screenshot, not a true live screencast.
- Rename settings and controls that imply live video so they describe snapshot refresh cadence.
- Surface CLI availability and setup actions where users encounter an empty dashboard.

Status: started.

## Phase 2: True Live Screencast

- Add a persistent CDP page connection that can send commands and receive events without reconnecting for each action.
- Implement `Page.startScreencast` and `Page.stopScreencast` with frame acknowledgements.
- Render frames through a stable image surface that avoids SwiftUI layout churn.
- Keep screenshot polling as a fallback when screencast startup fails.
- Add tests for frame parsing, acknowledgement, connection cancellation, and fallback behavior.

Status: started. The expanded session view now prefers `Page.startScreencast`, acknowledges frames, and falls back to screenshot polling when streaming fails. Remaining work: keep user input on the same persistent page connection and add renderer/performance QA with a real browser.

## Phase 3: Interaction Reliability

- Keep pointer and keyboard forwarding on the same persistent CDP connection used by the expanded session.
- Add clearer focus state and a visible interaction mode indicator.
- Add agent-active detection once incoming external CDP activity can be observed.
- Add manual and automated checks for click, scroll, typing, special keys, and coordinate mapping after resize.

Status: started. Pointer, scroll, and keyboard forwarding now use the same persistent page WebSocket as screencast frames when live screencast is active, with screenshot-polling command fallback still available. The GUI smoke covers click, scroll, typing, Enter, Backspace, and resize remapping; unit tests now cover special-key and modifier mapping before events are sent to CDP.

## Phase 4: QA and CI

- Produce coverage output in CI and retain it as an artifact.
- Upload packaged app artifacts from CI for every validated build.
- Add a scheduled CI run so toolchain drift is caught before a PR.
- Promote GUI smoke tests into a controlled CI job once runner accessibility and browser availability are stable.
- Add visual snapshots for dashboard empty state, populated grid, expanded snapshot view, settings, and error states.

Status: started. The expanded-session GUI smoke can run in live screencast mode or forced snapshot-fallback mode, and CI has an optional manual workflow for both. Main CI now also has a weekly scheduled run, manual dispatch, optional GUI smoke jobs, artifact-only visual snapshots, coverage/app artifacts, and retained build/test logs. Visual snapshots now produce a manifest, CI summary table, and non-blocking baseline status when `VISUAL_SNAPSHOT_BASELINE_DIR` is configured. Expanded toolbar icon controls now expose explicit accessibility labels and identifiers.

## Phase 5: Feature Completeness

- Add in-app navigation for the current session URL.
- Add multi-target/tab selection.
- Add detached session windows after the expanded view has stable streaming.
- Add recording only after screencast frames are available and performance is measured.

Status: planned.
