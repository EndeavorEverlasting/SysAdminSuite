# Production installation proof fixtures

These files are sanitized contract inputs only.

- `resume-matcher-live-accepted.fixture.json` has the shape of a successful non-fixture PR #222 acceptance result. CI must pass `--contract-fixture`, so it can produce only `contract-only` proof.
- `fixture-mode-rejected.fixture.json` proves that source evidence marked `fixture_mode: true` is blocked even when operator confirmation is supplied.

The fixtures contain no hostname, username, credential, provider secret, raw model output, real package path, corporate share, or production evidence.

A fixture result is never a production-installation claim. A live receipt requires the operator-local result, its exact SHA-256, explicit operator confirmation, and a non-fixture source result.
