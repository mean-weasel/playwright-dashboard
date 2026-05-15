# Realistic E2E And Demo Media Plan

This tranche uses the Operator Workbench fixture to produce local, reproducible
proof for future documentation and GitHub Pages work. It does not implement the
GitHub Pages site.

## Source Scenario

- Fixture: `fixtures/e2e-apps/operator-workbench`
- Smoke target: `RUN_REALISTIC_E2E_SMOKE=1 make smoke-realistic-e2e`
- Smoke artifacts: `dist/realistic-e2e-artifacts`
- Curated docs-media output: `dist/docs-media/operator-workbench`

The smoke starts an isolated local fixture server, opens a headed
`playwright-cli` Chrome session using an isolated daemon directory, launches
Playwright Dashboard in Safe mode, captures Dashboard artifacts, and drives
fixture route changes.

## Regenerate Media

After a package exists, regenerate realistic smoke artifacts:

```sh
RUN_REALISTIC_E2E_SMOKE=1 SMOKE_ARTIFACT_DIR=dist/realistic-e2e-artifacts make smoke-realistic-e2e
```

Create the curated docs-media bundle from existing smoke artifacts:

```sh
DEMO_MEDIA_FROM_EXISTING=1 make demo-media
```

Or run capture end to end:

```sh
make demo-media
```

## Current Media Inventory

- `dashboard-window.png`: primary screenshot candidate for future landing/docs.
- `scenario.json`: session, URL, and artifact metadata.
- `progress.log`: smoke timeline.
- `ui-snapshot.txt`: Accessibility snapshot evidence.
- `expanded-ready.json`: Dashboard readiness payload.

## Planned Media

- Short MP4 or GIF of the realistic fixture being observed in the expanded
  session view.
- Screenshot of the Dashboard session list with the realistic session card.
- Screenshot of the future docs/landing page using curated media.

## Curation Rules

- Do not commit generated binary media without explicit approval.
- Use only isolated local fixture sessions, not private user sessions.
- Review generated artifacts for local paths, ports, URLs, and unexpected
  private content before publication.
- Regenerate media after visible Dashboard or fixture UI changes.

## GitHub Pages Follow-up

A later tranche should implement the Pages site after the local scenario and
media pipeline are stable. That tranche should choose the static-site approach,
copy or generate approved media assets, and add a deployment workflow.
