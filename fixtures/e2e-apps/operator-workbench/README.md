# Operator Workbench Fixture

Operator Workbench is a deterministic static app used by Playwright Dashboard
smoke/demo scenarios. It is intentionally dependency-free so local and CI smoke
tests can serve it with any static HTTP server.

## Local Serve

From the repository root:

```sh
python3 -m http.server 41781 --directory fixtures/e2e-apps/operator-workbench
```

Then open:

```text
http://127.0.0.1:41781/
```

## Covered States

- Work queue dashboard with cards, metrics, and a live visual pulse.
- Detail route via hash navigation.
- Modal review drawer.
- Form validation for an escalation workflow.
- Scrollable incident timeline and runbook content.
- Dynamic visual changes suitable for screenshot and recording checks.
