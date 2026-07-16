# Resume Matcher workstation fixtures

The executable contract suite creates temporary fixture roots at runtime instead
of storing application or provider data in the repository.

Fixture mode proves:

- mutation gates;
- idempotent `.env` creation and preservation;
- profile and result-schema boundaries;
- no process launch;
- no network or provider call;
- no sanitized PDF or live-runtime claim;
- `Accept` returns `action-required` with `live-runtime-required`.

Fixture mode does not prove WSL, Python 3.13 installation, Node 22 installation,
Chrome or Playwright behavior, backend/frontend health, saved provider state, or
provider connectivity.
