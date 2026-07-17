# Resume Matcher workstation deployment

SysAdminSuite owns an idempotent workstation deployment and acceptance path for
[`srbhr/Resume-Matcher`](https://github.com/srbhr/Resume-Matcher). This is a
source-built Windows WSL / Linux application workflow, separate from the Windows
EXE/MSI approved-software catalog.

## Supported execution domains

- Windows 11 with one explicitly selected non-Docker WSL distribution.
- Ubuntu or Debian Bash execution.
- Windows PowerShell 5.1 or PowerShell 7 as the WSL control surface.

macOS, Docker-only WSL distributions, automatic provider authentication, and
remote-target deployment are outside this workflow.

## Operator entrypoints

Use these front doors:

- `scripts/Invoke-SasResumeMatcherWorkstation.ps1` from Windows.
- `scripts/invoke-sas-resume-matcher-workstation-safe.sh` from WSL or Linux.
- `scripts/Test-SasResumeMatcherLiveAcceptance.ps1` or
  `scripts/test-sas-resume-matcher-live-acceptance.sh` for acceptance.

The file `scripts/invoke-sas-resume-matcher-workstation.sh` is the underlying
engine. Operator commands route through the safety layer so application updates,
provider cost, and runtime ownership remain explicit.

## Lifecycle

| Action | Purpose | Mutation gate |
|---|---|---|
| `Plan` | Read prerequisites and report missing layers | none |
| `Apply` | Install missing packages and synchronize dependencies | required |
| `Validate` | Verify runtimes, imports, browser fallback, and sanitized PDF export | none |
| `Start` | Reuse a healthy runtime or start the repo-owned tmux services | required |
| `Status` | Check backend and frontend health | none |
| `Stop` | Stop the repo-owned `resume-matcher` tmux session and verify endpoints stopped | required |
| `Accept` | Compose live installation, PDF, health, page, and provider proof | required |

`Plan` is always the default. `Apply`, `Start`, `Stop`, and `Accept` must be
explicitly authorized.

## Windows WSL commands

```powershell
# Read-only plan
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Plan `
  -Distro Ubuntu

# Install missing layers without silently updating an existing checkout
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Apply `
  -Distro Ubuntu `
  -AllowMutation

# Explicitly authorize a clean-clone fast-forward when an update is available
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Apply `
  -Distro Ubuntu `
  -AllowMutation `
  -AllowApplicationUpdate

# Validate and start
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Validate -Distro Ubuntu
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Start -Distro Ubuntu -AllowMutation

# Live acceptance without a provider request
pwsh -File .\scripts\Test-SasResumeMatcherLiveAcceptance.ps1 -Distro Ubuntu
```

A provider health test is a separate, potentially billable LLM test. It requires
both confirmations:

```powershell
pwsh -File .\scripts\Test-SasResumeMatcherLiveAcceptance.ps1 `
  -Distro Ubuntu `
  -RequireProviderHealth `
  -ConfirmProviderCharge
```

## Direct WSL or Linux commands

```bash
# Plan
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh --action Plan

# Apply without authorizing a checkout update
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh --action Apply --apply

# Apply and authorize a clean-clone fast-forward
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh \
  --action Apply --apply --allow-application-update

# Validate, start, status, and stop
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh --action Validate
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh --action Start --apply
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh --action Status
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh --action Stop --apply

# Acceptance without a provider request
bash scripts/test-sas-resume-matcher-live-acceptance.sh

# Acceptance with exactly one explicit provider request
bash scripts/test-sas-resume-matcher-live-acceptance.sh \
  --require-provider-health --confirm-provider-charge
```

See `docs/RESUME_MATCHER_LIFECYCLE_SAFETY.md` for the complete safety contract.

## What Apply automates

Apply installs or reuses:

- `ca-certificates`, `curl`, `git`, `build-essential`, `tmux`, and `python3`;
- `uv` and Python 3.13;
- NVM v0.40.6 and Node 22;
- backend dependencies through `uv sync --python 3.13`;
- frontend dependencies through `npm ci`.

The default application path is `~/dev/Resume-Matcher`.

A dirty Resume Matcher repository or dirty NVM repository is preserved and
blocks changes. An existing clean Resume Matcher clone is compared with the
configured remote branch. When a fast-forward is available, Apply returns
`application-update-authorization-required` unless the operator supplies
`--allow-application-update` or `-AllowApplicationUpdate`.

The workflow does not remove local data, uploaded resumes, application database
state, or saved provider configuration.

## Backend configuration and provider keys

When `apps/backend/.env` is absent, Apply copies `.env.example`. It clears only
the literal example placeholder:

```text
LLM_API_KEY=sk-your-api-key-here
```

The resulting field is:

```text
LLM_API_KEY=
```

An existing `.env` is preserved. SysAdminSuite never writes, reads, forwards, or
prints the real API key. Configure DeepSeek or another supported provider in the
Resume Matcher Settings page:

```text
http://localhost:3000/settings
```

Acceptance reads only the masked provider configuration. It records provider and
model names, not the masked key. Provider health is opt-in and requires a second
cost confirmation. The result never stores model output.

## Ubuntu 26.04 and Playwright 1.58

The recovered failure was:

```text
Playwright does not support chromium on ubuntu26.04-x64
```

The observed Resume Matcher revision pinned Playwright 1.58. Repeating
`uv run playwright install chromium` on Ubuntu 26.04 does not repair that release
boundary. Apply installs or reuses:

```text
google-chrome-stable
```

Validation calls Resume Matcher's own `app.pdf._launch_browser` fallback and
creates a sanitized PDF containing only an acceptance heading. It verifies the
`%PDF-` header and records file size and SHA-256 under:

```text
~/.local/state/sysadminsuite/resume-matcher/last-result.json
~/.local/state/sysadminsuite/resume-matcher/resume-matcher-live-acceptance.pdf
```

No resume, job posting, API key, or provider response is included.

## Live acceptance proof chain

`Accept` performs these checks in order:

1. Confirm the source tree, `.env`, frontend dependencies, Python 3.13, and Node 22.
2. Import FastAPI and Playwright from the managed backend environment.
3. Launch the browser fallback and generate the sanitized PDF.
4. Reuse an existing healthy runtime when ports 8000 and 3000 are already ready.
5. Otherwise start backend and frontend in the repo-owned tmux session.
6. Observe `http://localhost:8000/api/v1/health`.
7. Observe the frontend and expected `Resume Matcher` page identity.
8. Read masked provider configuration and require a saved key.
9. Optionally perform one provider health request after explicit cost confirmation.
10. Emit distinct proof flags in the result artifact.

Reusing an existing healthy runtime prevents a second instance from colliding
with a manually started backend or frontend. `Stop` never kills arbitrary
processes. If endpoints still answer after the managed tmux session is stopped,
the result is `unmanaged-runtime-still-running` and requires manual inspection.

Fixture mode never starts processes, contacts a provider, or claims live
acceptance.

## Recovered troubleshooting

### `uv` installed but command not found

The Astral installer places `uv` under `~/.local/bin`:

```bash
source "$HOME/.local/bin/env"
uv --version
```

### Wrong directory

Backend commands belong in `~/dev/Resume-Matcher/apps/backend`; frontend commands
belong in `~/dev/Resume-Matcher/apps/frontend`.

### Node missing in WSL

A Windows Node installation does not satisfy WSL. Apply installs NVM and selects
Node 22 before `npm ci`.

### Python version drift

The validated environment uses Python 3.13 through `uv python install 3.13` and
`uv sync --python 3.13`.

### The backend looked hung and captured arrow keys

`RELOAD=true uv run app` is a foreground server. It keeps the terminal attached
to Uvicorn until `Ctrl+C`; arrow keys appear as escape sequences. Start uses
detached tmux windows instead.

### LiteLLM botocore warnings

Warnings that Bedrock or SageMaker event-stream decoding is unavailable because
`botocore` is absent are non-fatal when those AWS providers are not used.

### DeepSeek test returned Chinese reasoning

Resume Matcher's connection test can display a reasoning field when the normal
answer is empty or truncated. The provider request can still succeed. Acceptance
never stores that output; generated content remains controlled by the app's
content-language setting.

## Proof ceiling

Fixture and CI checks prove schemas, syntax, mutation gates, update authorization,
cost confirmation, idempotent `.env` handling, unmanaged-runtime reporting, and
false-proof prevention. They do not prove the user's workstation, provider
account, uploaded resume, or real job comparison.

Only a successful non-fixture `Accept` run proves the local browser, sanitized
PDF, backend health, frontend page identity, and saved provider configuration.
Only `Accept` with both provider-health and cost-confirmation flags proves that
the configured provider responded at that moment.
