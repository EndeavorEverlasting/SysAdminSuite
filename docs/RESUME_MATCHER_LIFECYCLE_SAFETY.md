# Resume Matcher lifecycle safety

Use `scripts/invoke-sas-resume-matcher-workstation-safe.sh` or the PowerShell
`Invoke-SasResumeMatcherWorkstation.ps1` wrapper for operator actions. The older
`invoke-sas-resume-matcher-workstation.sh` file is the lifecycle engine; the safe
front door adds authorization and ownership checks around it.

## 1. Application updates are separate from installation

`Apply` may install missing packages and synchronize dependencies, but it does
not fast-forward an existing clean Resume Matcher checkout unless the operator
adds a second authorization flag.

```bash
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh \
  --action Apply \
  --apply
```

When the local checkout differs from the remote branch, that command returns
`action-required` with:

```text
application-update-authorization-required
```

Authorize the clean-clone fast-forward explicitly:

```bash
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh \
  --action Apply \
  --apply \
  --allow-application-update
```

Windows WSL equivalent:

```powershell
pwsh -File .\scripts\Invoke-SasResumeMatcherWorkstation.ps1 `
  -Action Apply `
  -Distro Ubuntu `
  -AllowMutation `
  -AllowApplicationUpdate
```

Dirty repositories remain blocked and are never reset. If the remote revision
cannot be checked safely, Apply also stops without changing the checkout.

## 2. Provider health has a separate cost confirmation

Normal `Accept` verifies that a saved provider configuration exists without
issuing an LLM request. The opt-in test performs one provider request and may
consume credits, so two explicit flags are required:

```bash
bash scripts/test-sas-resume-matcher-live-acceptance.sh \
  --require-provider-health \
  --confirm-provider-charge
```

PowerShell equivalent:

```powershell
pwsh -File .\scripts\Test-SasResumeMatcherLiveAcceptance.ps1 `
  -Distro Ubuntu `
  -RequireProviderHealth `
  -ConfirmProviderCharge
```

`--require-provider-health` without `--confirm-provider-charge` fails before the
provider endpoint is called. SysAdminSuite never reads or writes the API key and
never stores the model response.

## 3. Stop reports unmanaged runtimes instead of killing them

`Stop` terminates only the repo-owned `resume-matcher` tmux session. SysAdminSuite
never kills arbitrary processes by port, name, or PID.

```bash
bash scripts/invoke-sas-resume-matcher-workstation-safe.sh \
  --action Stop \
  --apply
```

After stopping the managed session, the safe front door probes the configured
backend and frontend endpoints for a bounded interval. If either endpoint still
answers, the result is `action-required` with:

```text
unmanaged-runtime-still-running
```

That result means a backend or frontend was started outside the managed tmux
session, or another process owns a configured port. Inspect the process manually
before stopping it. SysAdminSuite deliberately does not guess which external
process is safe to terminate.

## Evidence boundary

Fixture tests prove update authorization, cost confirmation, and unmanaged
runtime reporting without contacting GitHub, DeepSeek, or a live application.
Only a real workstation run proves the local checkout, provider account, and
process ownership state.
