# Auto-logon Workstation Assessment

Read-only batch assessment for Northwell shared-workstation auto-logon posture. Maps legacy Alex install gates to SysAdminSuite evidence checks using fake sample hostnames only in committed fixtures.

## Alex Reference Mapping

| Alex artifact | Signal | SysAdminSuite check |
|---|---|---|
| `Alex Emulation/Alex/SSUH_Pavilion_Install.cmd` lines 9–18 | `reg query HKLM\SOFTWARE\NSLIJHS\PostInstall /v SetAutoLogon` contains `Autologon_YES` | Remote `reg.exe` PostInstall probe → `PostInstall_SetAutoLogon`, `PostInstall_Raw` |
| Same script | Else branch → "No Auto-Logon needed" | `OverallStatus=shared_device` when intent marker absent |
| Same script | Launches `NW_AutoLogon_Setup_x64.exe` when intent present | Winlogon keys must match hostname after setup → `Winlogon_AutoAdminLogon`, `Winlogon_DefaultUserName`, `Hostname_User_Match` |
| Northwell OU policy (`Managed_Shared`) | Shared kiosks live under `\_Workstations\Managed_Shared\` | `AD_Computer_OU`, `Legacy_OU_Warning`, `ou_mismatch` when intent + wrong OU |
| AD account per hostname | Short hostname maps to dedicated user | `--ad-live` via `survey/sas-ad-identity-export.ps1 --lookup-hostname-as-user` → `AD_User_Found`, `account_missing` |

## Assessment Lifecycle

1. **Reachability** — ping + admin share (`\\HOST\c$`) or `bash/transport/sas-network-preflight.sh`.
2. **PostInstall intent** — `HKLM\SOFTWARE\NSLIJHS\PostInstall\SetAutoLogon` contains `Autologon_YES`.
   - No intent → `shared_device`.
3. **When intent present**
   - AD user for short hostname missing → `account_missing`.
   - Winlogon `AutoAdminLogon` not `1` or `DefaultUserName` ≠ hostname → `setup_incomplete`.
   - Computer OU not under `Managed_Shared` → `ou_mismatch`.
   - PostInstall intent only (no Winlogon keys yet) with AD + OU OK → `intent_only`.
   - All checks pass → `autologon_ready`.
4. **Transport failures** — no ping/admin share → `unreachable`.
5. **Probe errors** — reachable but registry query fails → `probe_failed`.

## OverallStatus Values

| Status | Meaning |
|---|---|
| `shared_device` | No auto-logon intent in PostInstall |
| `autologon_ready` | Intent, AD user, Winlogon, and OU aligned |
| `intent_only` | PostInstall intent recorded; Winlogon not configured yet |
| `account_missing` | Intent present but AD user for hostname not found |
| `setup_incomplete` | Intent present but Winlogon not aligned to hostname |
| `ou_mismatch` | Intent present but computer OU not under Managed_Shared |
| `unreachable` | Host offline or admin share unavailable |
| `probe_failed` | Reachable but registry evidence could not be read |

## Evidence Contract (CSV)

Output columns:

`Timestamp`, `HostName`, `Reachability`, `AdminShareOk`, `PostInstall_SetAutoLogon`, `PostInstall_Raw`, `Winlogon_AutoAdminLogon`, `Winlogon_DefaultUserName`, `Hostname_User_Match`, `AD_User_Found`, `AD_Computer_OU`, `Legacy_OU_Warning`, `OverallStatus`, `AssessmentStage`, `ProbeMethod`, `EvidenceDetail`, `RevisitRecommendation`

Fixture input manifest: `survey/fixtures/autologon_manifest.sample.csv` (fake hosts `SAMPLE301MSO001`–`SAMPLE301MSO008`).

## Commands

### Batch assessment (WBS manifest)

```bash
bash survey/sas-assess-autologon.sh \
  --manifest survey/fixtures/autologon_manifest.sample.csv \
  --output survey/output/autologon_assessment.csv \
  --dashboard survey/output/autologon_dashboard.html \
  --open
```

### With live AD evidence

```bash
bash survey/sas-assess-autologon.sh \
  --manifest ./survey/output/wbs_targets.csv \
  --ad-live \
  --output survey/output/autologon_assessment.csv \
  --dashboard survey/output/autologon_dashboard.html
```

### Local workstation (technician on-box)

```bash
bash survey/sas-assess-autologon.sh --local --output survey/output/autologon_local.csv --open
```

### CI / contract tests (no reg.exe required)

```bash
bash survey/sas-assess-autologon.sh \
  --manifest survey/fixtures/autologon_manifest.sample.csv \
  --fixture-dry-run \
  --output survey/output/autologon_assessment.csv \
  --dashboard survey/output/autologon_dashboard.html
```

```bash
bash deployment-audit/tests/test_autologon_assessment_contracts.sh
```

## Safety

- Read-only. No registry writes, no auto-logon setup, no AD mutations.
- Do not commit CSV/HTML outputs from live runs — they may contain real hostnames, usernames, and OU paths.
- `Alex Emulation/` is reference-only and gitignored.

## Related Files

| File | Role |
|---|---|
| `survey/sas-assess-autologon.sh` | Batch orchestrator |
| `deployment-audit/sas-render-autologon-dashboard.py` | HTML dashboard |
| `survey/sas-ad-identity-export.ps1` | Optional AD user + computer OU export |
| `bash/transport/sas-network-preflight.sh` | Optional network preflight |
| `deployment-audit/tests/test_autologon_assessment_contracts.sh` | Contract tests |
