# Resume Matcher Workstation Deployment

This runbook is the operator contract for installing and running
[`srbhr/Resume-Matcher`](https://github.com/srbhr/Resume-Matcher) through
SysAdminSuite on a Windows workstation with WSL, or directly from a supported
Linux shell.

## Scope and proof boundary

The service owns:

- read-only planning and current-state inventory;
- idempotent installation of missing workstation prerequisites;
- a pinned Python 3.13 project environment managed by `uv`;
- Node 22 managed by a preserved or pinned NVM installation;
- a clean clone or fast-forward update of Resume Matcher;
- safe `.env` creation without writing provider credentials;
- the Ubuntu 26.04 system-Chrome fallback required by the repository's pinned
  Playwright 1.58 dependency;
- frontend and backend dependency installation;
- bounded tmux start, status, stop, and validation operations;
- ignored local JSON results that separate configuration, launch, health, and
  live-runtime proof.

The service never writes an API key, performs automatic authentication, uploads
a resume, chooses an LLM provider, or claims application acceptance on the
operator's behalf. DeepSeek and other provider credentials remain a manual
Settings UI step at `http://localhost:3000/settings`.

## Files

| Role | Path |
|---|---|
| Deployment profile | `Config/resume-matcher-workstation.sample.json` |
| Profile schema | `schemas/harness/resume-matcher-workstation.schema.json` |
| Result schema | `schemas/harness/resume-matcher-workstation-result.schema.json` |
| Linux/WSL service | `scripts/invoke-sas-resume-matcher-workstation.sh` |
| Windows WSL wrapper | `scripts/Invoke-SasResumeMatcherWorkstation.ps1` |
| Contract tests | `Tests/survey/test_resume_matcher_workstation_contracts.py` |

Runtime state defaults to
`~/.local/state/sysadminsuite/resume-matcher/` and is not a tracked evidence
location.

## Operator workflow

### Windows PowerShell entrypoint

Plan is read-only and is always the first command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Plan
```

Install or repair missing prerequisites and application dependencies:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Apply -AllowMutation
```

Validate pinned runtimes, backend imports, `.env` safety, and browser launch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Validate
```

Start the backend and frontend in the repo-owned `resume-matcher` tmux session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Start -AllowMutation
```

Check health or stop the owned session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 -Action Stop -AllowMutation
```

When more than one non-Docker WSL distribution exists, pass `-Distro Ubuntu`
or the exact distribution name. The wrapper refuses to guess.

### Direct Linux or WSL Bash entrypoint

```bash
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Plan
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Apply --apply
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Validate
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Start --apply
bash scripts/invoke-sas-resume-matcher-workstation.sh --action Status
```

Open `http://localhost:3000` only after `Status` reports both backend and
frontend health.

## Automated configuration sequence

Apply performs the following bounded sequence:

1. On Ubuntu or Debian, install only missing base prerequisites through the
   distro package manager: `ca-certificates`, `curl`, `git`, `build-essential`,
   `tmux`, and `python3`.
2. Reuse `uv` when already available. Otherwise download the official installer
   to a temporary file and execute that file. The service does not use a
   `curl | sh` pipeline.
3. Reuse an existing NVM installation when valid. Otherwise clone the official
   NVM repository at `v0.40.6`. Existing unknown NVM directories are preserved
   and treated as an action-required condition.
4. Install and select Node 22.
5. Clone `https://github.com/srbhr/Resume-Matcher.git` at `main`, or update an
   existing clean clone with `git pull --ff-only`. A dirty application repo is
   preserved and blocks automated update.
6. Install Python 3.13 through `uv`, then run `uv sync --python 3.13` in
   `apps/backend`.
7. Create `.env` only when missing. The exact example placeholder is converted
   from `LLM_API_KEY=sk-your-api-key-here` to `LLM_API_KEY=`. Existing real or
   operator-managed values are not overwritten.
8. Install the browser runtime. Ubuntu 26.04 uses system
   `google-chrome-stable`; other supported releases use
   `uv run playwright install chromium`.
9. Run `npm ci` in `apps/frontend` using Node 22.
10. Emit a result that does not promote fixture or configuration proof to live
    runtime proof.

## Troubleshooting recovered from the manual proof

### `uv` installed but the command is not found

The official installer writes `uv` beneath `~/.local/bin`. Load its environment
for the current shell:

```bash
source "$HOME/.local/bin/env"
uv --version
```

The deployment service performs this automatically. Do not install a second
classic-confined Snap merely because the current shell has not refreshed PATH.

### Global Python reports 3.14

Resume Matcher currently declares Python 3.13+ and includes a repository-local
3.13 version contract. The service intentionally creates the backend virtual
environment with Python 3.13 even when the workstation's global `python3`
reports 3.14.

Validation must show a backend interpreter under:

```text
~/dev/Resume-Matcher/apps/backend/.venv/bin/python
```

### Node is missing while `npm` appears to exist

Do not infer a valid runtime from a stray `npm` command. The service loads NVM,
installs Node 22, selects it, and validates both `node --version` and
`npm --version` from the same NVM tree.

### Ubuntu 26.04 rejects the Playwright Chromium download

The repository pins Playwright 1.58. On Ubuntu 26.04 that version may report:

```text
Playwright does not support chromium on ubuntu26.04-x64
```

This is not an `apt` prerequisite failure. Resume Matcher already falls back to
a system browser when the bundled executable is absent. The service therefore
installs `google-chrome-stable` on Ubuntu 26.04 and Validate exercises the
application's own `app.pdf._launch_browser` function.

### The backend command appears hung and captures arrow keys

`RELOAD=true uv run app` is a foreground server. Once Uvicorn reports
`Application startup complete`, the terminal is serving logs and requests.
Arrow keys may appear as escape sequences because the shell is not accepting
commands. The service avoids this operator trap by running backend and frontend
in dedicated tmux windows.

### LiteLLM warns that `botocore` is missing

Warnings about Bedrock or SageMaker event-stream decoding are non-fatal when
using DeepSeek, OpenRouter, OpenAI, Gemini, Anthropic, Groq, Ollama, or another
non-AWS provider. Do not install `botocore` solely to silence those optional
provider warnings.

### The health test returns Chinese reasoning text

A successful provider test proves connectivity even when a reasoning model's
short `Hi` response is surfaced from `reasoning_content` and appears in Chinese.
Set content generation to English in Resume Matcher. Normal resume-generation
prompts include the configured output language; the tiny connection test does
not provide the same language context.

## Post-install DeepSeek configuration

After Start and Status succeed:

1. Open `http://localhost:3000/settings`.
2. Select **DeepSeek**.
3. Enter a currently supported DeepSeek model name.
4. Paste the API key into the Settings UI.
5. Leave Base URL blank unless an approved proxy is intentionally used.
6. Test the connection, save, refresh system status, and confirm the LLM card is
   connected.

The deployment service deliberately leaves `LLM_API_KEY=` blank in `.env` so
an environment-level placeholder or stale key cannot override Resume Matcher's
encrypted per-provider key store.

## Health and runtime proof

Backend liveness:

```bash
curl --fail --silent --show-error http://localhost:8000/api/v1/health
```

Frontend readiness:

```bash
curl --fail --silent --show-error --output /dev/null http://localhost:3000
```

Proof levels remain separate:

- fixture Apply proves idempotent file configuration only;
- Validate proves pinned runtimes, imports, environment safety, and browser
  launch capability;
- Start plus both bounded health checks proves the services are live;
- opening the dashboard, configuring a provider, uploading a resume, tailoring,
  and exporting a PDF require separate observed product acceptance.
