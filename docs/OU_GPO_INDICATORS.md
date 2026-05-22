# SysAdminSuite OU/GPO Indicator Collector

## Purpose

`scripts/sas_ou_gpo_indicators.sh` collects OU and Group Policy posture indicators where available.

It follows:

```text
Recon -> Decide -> Act -> Log -> Export
```

This module is intentionally read-only. It collects evidence and exports indicators. It does not mutate Active Directory, local policy, or Group Policy.

## Why This Exists

Many field failures look like product failures until workstation posture is checked.

Common examples:

- wrong OU
- missing Group Policy
- expected GPO not applied
- domain posture unclear
- machine on the wrong network segment
- user OU confused with computer OU
- missing domain controller reachability

This collector creates evidence before anyone starts guessing.

## File

```text
scripts/sas_ou_gpo_indicators.sh
```

## Command Examples

Default local run:

```bash
bash scripts/sas_ou_gpo_indicators.sh
```

Reference-host label:

```bash
bash scripts/sas_ou_gpo_indicators.sh --target-hint WMH300OPR024
```

Skip registry evidence:

```bash
bash scripts/sas_ou_gpo_indicators.sh --no-registry
```

Dry run:

```bash
bash scripts/sas_ou_gpo_indicators.sh --dry-run
```

## Evidence Commands

The module uses Bash-on-Windows wrappers around Windows-native executables:

```bash
hostname.exe
whoami.exe
whoami.exe /user /fo list
whoami.exe /groups /fo list
whoami.exe /fqdn
cmd.exe /c set
wmic.exe computersystem get domain,partofdomain /format:list
gpresult.exe /r /scope computer
gpresult.exe /r /scope user
nltest.exe /dsgetdc:<USERDNSDOMAIN>
reg.exe query "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\State\\Machine" /s
reg.exe query "HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\State" /s
```

## Guardrails

- no `gpupdate`
- no AD writes
- no local policy changes
- no registry writes
- no PowerShell cmdlets
- no remote host mutation
- no interpretation that user OU equals computer OU

## Output Layout

Runs write to:

```text
$USERPROFILE/SysAdminSuite/Runs/SAS_OU_GPO_INDICATORS_<HOSTNAME>_<TIMESTAMP>/
```

Key outputs:

```text
logs/ou_gpo_events.jsonl
logs/ou_gpo_trace.log
raw/
exports/command_plan.txt
exports/ou_gpo_indicators.csv
exports/ou_gpo_summary.env
exports/ou_gpo_report.md
exports/ou_gpo_report.json
exports/ou_gpo_recommended_actions.md
exports/applied_computer_gpos.txt
exports/applied_user_gpos.txt
exports/security_groups.txt
```

## Indicators

| Indicator | Meaning |
|---|---|
| `domain_posture` | Whether local evidence suggests domain joined posture. |
| `domain` | Domain from WMIC or environment fallback. |
| `logon_server` | Current logon server hint. |
| `domain_controller_indicator` | Best-effort DC evidence from gpresult or nltest. |
| `computer_ou_path_hint` | Parsed computer OU path hint, not AD truth. |
| `user_ou_path_hint` | Parsed user OU path hint. Keep separate from computer OU. |
| `applied_computer_gpo_count` | Count of parsed applied computer GPOs. |
| `applied_user_gpo_count` | Count of parsed applied user GPOs. |
| `security_group_count` | Advisory count from gpresult and whoami group evidence. |

## Correct Use

Use this module to support the next decision:

```text
Does this workstation look like it is in the expected OU/GPO posture?
```

Do not use it as final proof. It is evidence collection, not AD truth.

## Safe Next Workflow

1. Run this module on the target host.
2. Run it on a known-good reference host if available.
3. Compare computer OU path hints, applied computer GPOs, and domain controller evidence.
4. Draft a ServiceNow/AD request with source host and target host clearly separated.
5. Attach only safe excerpts when sharing externally.

WMIC and gpresult can fail or omit fields depending on permissions, cached policy, build, or network posture. Classify that as incomplete evidence first, not product failure.
