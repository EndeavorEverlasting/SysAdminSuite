# Resume Matcher workstation deployment

SysAdminSuite owns an idempotent workstation deployment and acceptance path for
[`srbhr/Resume-Matcher`](https://github.com/srbhr/Resume-Matcher). This is a
source-built Windows WSL / Linux application workflow. It is intentionally
separate from the Windows EXE/MSI approved-software catalog.

## Supported execution domains

- Windows 11 with one explicitly selected non-Docker WSL distribution.
- Ubuntu or Debian Bash execution.
- Windows PowerShell 5.1 or PowerShell 7 as the WSL control surface.

macOS, Docker-only WSL distributions, automatic provider authentication, and
remote target deployment are outside this workflow.

## Lifecycle

| Action | Purpose | Mutation gate |
|---|---|---|
| `Plan` | Read current prerequisites and report missing layers | none |
| `Apply` | Install missing packages, clone/update the app, and sync dependencies | required |
| `Validate` | Verify runtimes, imports, browser fallback, and sanitized PDF export | none |
| `Start` | Reuse a healthy runtime or start the repo-owned tmux services | required |
| `Status` | Check backend and frontend health | none |
| `Stop` | Stop only the repo-owned `resume-matcher` tmux session | required |
| `Accept` | Compose live installation, PDF, health, page, and provider proof | required |

`Plan` is always the default. `Apply`, `Start`, `Stop`, and `Accept` must be
explicitly authorized.

## Windows WSL commands

From the SysAdminSuite repository in PowerShell:

```powershell
# Read-only plan
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Plan `
  -Distro Ubuntu

# Install or repair missing layers
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Apply `
  -Distro Ubuntu `
  -AllowMutation

# Validate the installed application and sanitized PDF path
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Validate `
  -Distro Ubuntu

# Start or reuse the runtime
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Start `
  -Distro Ubuntu `
  -AllowMutation
```

The stable one-command live acceptance entrypoint is:

```powershell
pwsh -File .\scripts\Test-SasResumeMatcherLiveAcceptance.ps1 `
  -Distro Ubuntu
```

That command checks that a provider key is saved, but it does not issue an LLM
request. To opt into one bounded provider health request:

```powershell
pwsh -File .\scripts\Test-SasResumeMatcherLiveAcceptance.ps1 `
  -Distro Ubuntu `
  -RequireProviderHealth
```

`-RequireProviderHealth` may consume provider credits. It is the only acceptance
mode that performs the billable LLM test.

## Direct WSL or Linux commands

```bash
# Read-only plan
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Plan

# Install or repair
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Apply --apply

# Validate
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Validate

# Start or reuse an existing healthy runtime
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Start --apply

# Live acceptance without a provider request
bash scripts/test-sas-resume-matcher-live-acceptance.sh

# Live acceptance including one explicit provider request
bash scripts/test-sas-resume-matcher-live-acceptance.sh --require-provider-health
```

## What Apply automates

Apply installs or reuses:

- `ca-certificates`
- `curl`
- `git`
- `build-essential`
- `tmux`
- `python3`
- `uv`
- Python 3.13
- NVM v0.40.6
- Node 22
- backend dependencies through `uv sync --python 3.13`
- frontend dependencies through `npm ci`

The deployment profile is
`Config/resume-matcher-workstation.sample.json`. The default application path is
`~/dev/Resume-Matcher`.

Existing clean clones are fast-forwarded. A dirty Resume Matcher repository or
dirty NVM repository is preserved and blocks the update instead of being reset.
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
Resume Matcher Settings page at:

```text
http://localhost:3000/settings
```

The live acceptance command reads only the application's masked provider
configuration response. It records the provider and model names, not the masked
key. The optional provider health mode sends a stored-configuration test to
Resume Matcher and discards the returned model output instead of writing it to
the acceptance artifact.

## Ubuntu 26.04 and Playwright 1.58

The manually proven failure was:

```text
Playwright does not support chromium on ubuntu26.04-x64
```

The repository version of Resume Matcher pinned Playwright 1.58 during the
observed setup. Repeating `uv run playwright install chromium` on Ubuntu 26.04
does not repair that release boundary.

The deployment therefore installs or reuses system Chrome:

```text
google-chrome-stable
```

Validation calls Resume Matcher's own `app.pdf._launch_browser` fallback and
then creates a sanitized PDF containing only an acceptance heading. It verifies
the `%PDF-` header, records the file size and SHA-256, and stores the artifact
under the ignored workstation state root.

Default state paths are:

```text
~/.local/state/sysadminsuite/resume-matcher/last-result.json
~/.local/state/sysadminsuite/resume-matcher/resume-matcher-live-acceptance.pdf
```

No resume, job posting, API key, or provider response is included in that
sanitized PDF.

## Live acceptance proof chain

`Accept` performs these checks in order:

1. Confirm the source tree, `.env`, frontend dependencies, Python 3.13, and Node 22.
2. Import FastAPI and Playwright from the managed backend environment.
3. Launch Resume Matcher's browser fallback and generate the sanitized PDF.
4. Reuse an existing healthy runtime when ports 8000 and 3000 are already ready.
5. Otherwise start backend and frontend in the repo-owned `resume-matcher` tmux session.
6. Observe `http://localhost:8000/api/v1/health`.
7. Observe the frontend and the expected `Resume Matcher` page identity.
8. Read the masked provider configuration and require a saved key.
9. Optionally perform one explicit provider health request.
10. Emit a schema-validated result with distinct proof flags.

Reusing an existing healthy runtime is deliberate. It prevents a second tmux
session from colliding with the manually started backend or frontend that may
already own the ports.

Fixture mode never starts processes, contacts a provider, or claims live
acceptance. It returns `action-required` with `live-runtime-required`.

## Recovered troubleshooting

### `uv` installed but command not found

The Astral installer places `uv` under `~/.local/bin`. Reload it with:

```bash
source "$HOME/.local/bin/env"
uv --version
```

The automation performs this reload before using `uv`.

### Wrong directory

The backend commands belong in:

```text
~/dev/Resume-Matcher/apps/backend
```

The frontend commands belong in:

```text
~/dev/Resume-Matcher/apps/frontend
```

Apply validates those paths after cloning.

### Node missing in WSL

A Windows Node installation does not satisfy WSL. Apply installs NVM v0.40.6
inside WSL and selects Node 22 before `npm ci`.

### Python version drift

The validated environment uses Python 3.13. Apply runs:

```text
uv python install 3.13
uv sync --python 3.13
```

Validate confirms the backend interpreter reports Python 3.13.

### The backend looked hung and captured arrow keys

`RELOAD=true uv run app` is a foreground server. It keeps that terminal attached
to Uvicorn until `Ctrl+C`. Arrow keys typed into the foreground server appear as
escape sequences. The automated Start action launches backend and frontend in
detached tmux windows instead.

### LiteLLM botocore warnings

Warnings that Bedrock or SageMaker event-stream decoding is unavailable because
`botocore` is absent are non-fatal when those AWS providers are not in use. The
deployment does not add AWS dependencies merely to hide unrelated warnings.

### DeepSeek test returned Chinese reasoning

Resume Matcher's connection test can fall back to a reasoning field when the
normal answer is empty or truncated. A Chinese reasoning trace after the prompt
`Hi` still proved that the provider request succeeded. The live acceptance
artifact never stores that model output. Actual generated resume content remains
controlled by Resume Matcher's content-language setting.

## Proof ceiling

Fixture and CI checks prove schemas, syntax, mutation gates, idempotent `.env`
handling, false-proof prevention, and command composition. They do not prove the
user's workstation, provider account, uploaded resume, real job comparison, or
PDF content generated from personal data.

Only a successful non-fixture `Accept` run proves the local browser, sanitized
PDF, backend health, frontend page identity, and saved provider configuration.
Only `Accept` with `--require-provider-health` or `-RequireProviderHealth` proves
that the configured provider responded at that moment.
