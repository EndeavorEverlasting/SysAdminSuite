# Deployment Orchestration Validation Report

Date: 2026-07-07

## Proof taxonomy

- Contract proof: manifest schema, operation policy, render-only classifier configs, examples, fixture manifest, and runbook define the required behavior and forbidden operations.
- Static test proof: pytest contract tests inspect script/config/docs/fixtures for safety guards, output shape, gitignore coverage, dry-run fixture integrity, validator default safety, and forbidden log/security mutation patterns.
- Harness proof: delimiter-balance check confirms the PowerShell script has balanced structural delimiters in this Linux container.
- Runtime proof: not claimed; no authorized live Windows/WinRM target environment was available in this container, and `pwsh` was not installed for local PowerShell execution.

## Commands run

```bash
git status --short --branch
```

Result before this validation pass: clean on `work` (`## work`).

```bash
git log --oneline -5
```

Result included prior sprint commit `fda8415 Add authorized app deployment orchestration lane`.

```bash
pwsh -NoProfile -Command '$PSVersionTable'
```

Result: `/bin/bash: pwsh: command not found`. PowerShell validation was not available in this environment.

```bash
python -m pytest Tests/deployment/test_authorized_app_deployment_contracts.py -q
```

Initial result after adding the dry-run fixture contract: `1 failed, 9 passed`; the failure was an incorrect Python string escape in the new fixture assertion, not a product script failure.

```bash
python -m pytest Tests/deployment/test_authorized_app_deployment_contracts.py -q
```

Final result: `10 passed`.

```bash
python - <<'PY'
from pathlib import Path
p=Path('scripts/Invoke-AuthorizedAppDeployment.ps1').read_text()
pairs={'{':'}','(':')','[':']'}
stack=[]
for i,ch in enumerate(p):
    if ch in pairs: stack.append((ch,i))
    elif ch in pairs.values():
        if not stack: raise SystemExit(f'unmatched {ch} at {i}')
        o,j=stack.pop()
        if pairs[o]!=ch: raise SystemExit(f'mismatch {o}@{j} {ch}@{i}')
if stack: raise SystemExit(f'unclosed {stack[-1]}')
print('delimiter balance ok')
PY
```

Result: `delimiter balance ok`.

```bash
rg -n "Clear-EventLog|Remove-EventLog|wevtutil\s+cl|Get-WinEvent\s+-ComputerName|Set-MpPreference\s+.*Disable|Stop-Service\s+.*(Defender|WinDefend|EDR)|Disable-.*Audit|Remove-Item\s+.*\.evtx|Start-Process\s+.*Hidden|WindowStyle\s+Hidden|Remove-Item\s+.*\$PSCommandPath|Remove-Item\s+.*Invoke-AuthorizedAppDeployment" scripts config docs examples -g "!docs/deployment-validation-report.md" -g "!docs/deployment-handoff-prompt.md" || true
```

Result: no matches in product scripts/config/docs/examples.

```bash
git check-ignore -v output/deployments/fixture-dry-run/deployment-results.json
```

Result: runtime deployment outputs are ignored by `.gitignore`.

```bash
pwsh -NoProfile -File scripts/validate-deployment-config.ps1
```

Result: `/bin/bash: pwsh: command not found`; skipped due to missing PowerShell runtime.

```bash
pwsh -NoProfile -File scripts/validate-log-policy.ps1
```

Result: `/bin/bash: pwsh: command not found`; skipped due to missing PowerShell runtime.

## Dry-run fixture closeout

A sanitized local fixture was added for future Windows/PowerShell validation:

- `Tests/fixtures/deployment/fixture-installer.txt`
- `Tests/fixtures/deployment/deployment-manifest.fixture.json`

The fixture uses a fake hostname, a synthetic example UNC share path, an absolute local fixture installer path, and a matching SHA256. The validator now defaults to this fixture with deployment ID `fixture-dry-run`, `-TargetLimit 1`, and no `-Execute` flag.

## Skipped checks

- PowerShell parser validation: skipped because `pwsh` is not installed in this container.
- PowerShell dry-run fixture execution: skipped because `pwsh` is not installed in this container.
- `scripts/validate-deployment-config.ps1` execution: skipped because `pwsh` is not installed in this container.
- `scripts/validate-log-policy.ps1` execution: skipped because `pwsh` is not installed in this container.
- PSScriptAnalyzer: skipped because PowerShell is unavailable and no repo dependency bootstrap pattern was used to install new dependencies.
- Live deployment execution: skipped because no authorized Windows/WinRM target environment or approved internal installer share is available in this container.

## Final decision

Ready for Windows dry-run review. Not ready for execute mode until Windows parser checks, PowerShell validator execution, dry-run fixture proof under PowerShell, and an approved internal test environment are confirmed.

---

## Validation result triage update — 2026-07-07

### Evidence reviewed

No additional Windows validation output was present in the repository or prompt beyond the prior Linux/container validation artifacts. I re-ran the available local checks in this container to confirm the closeout baseline did not regress.

### Triage against sprint gates

| Gate | Evidence | Decision |
|---|---|---|
| PowerShell parser result | Not available; `pwsh` is not installed in this container. | Blocked pending Windows/PowerShell validation. |
| `validate-deployment-config.ps1` result | Not executable here because `pwsh` is unavailable. | Blocked pending Windows/PowerShell validation. |
| `validate-log-policy.ps1` result | Not executable here because `pwsh` is unavailable. | Blocked pending Windows/PowerShell validation. |
| Dry-run fixture result | Fixture contract is present and static tests pass; PowerShell dry-run execution is not available here. | Ready for Windows dry-run review, not yet approved test-host dry-run. |
| PSScriptAnalyzer | Not available because PowerShell is unavailable and no dependency install was performed. | Documented skip. |
| Python contract tests | `python -m pytest Tests/deployment/test_authorized_app_deployment_contracts.py -q` → `10 passed`. | Passed static test proof. |
| Destructive-pattern safety review | `rg` safety review returned no product matches. | Passed static safety review. |
| Generated output paths | `git check-ignore -v output/deployments/fixture-dry-run/deployment-results.json` confirms deployment outputs are gitignored. | Passed artifact hygiene check. |
| Git status | `git status --short --branch` was clean before this report update. | Passed repo hygiene check before documentation update. |

### Current gate decision

Needs Windows validation evidence before moving to approved test-host dry-run. The lane remains ready for Windows dry-run review, but it is not yet ready for approved test-host dry-run and is not ready for production execute.

### Required next evidence

Run these from a Windows validation workstation with PowerShell available, using the sanitized fixture first and without `-Execute`:

```powershell
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  "scripts/Invoke-AuthorizedAppDeployment.ps1",
  [ref]$tokens,
  [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) { $errors | Format-List *; exit 1 }
"PowerShell parser validation passed"
```

```powershell
pwsh -NoProfile -File scripts/validate-deployment-config.ps1
```

```powershell
pwsh -NoProfile -File scripts/validate-log-policy.ps1
```

```powershell
Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue
```

If `Invoke-ScriptAnalyzer` is available:

```powershell
Invoke-ScriptAnalyzer -Path scripts/Invoke-AuthorizedAppDeployment.ps1 -Recurse
```

Only after those pass should the next gate be reconsidered as: ready for approved test-host dry-run; not ready for production execute.
