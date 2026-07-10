# Cybernet COM AutoFix usability closure

## Sprint outcome

PR #156 includes the requested hardening for the Cybernet COM AutoFix lane:

- progress/status output to avoid ambiguous hanging prompts
- per-device `Device Parameters` registry export before `PortName` changes
- explicit native registry export exit-code, file-presence, and nonempty-file validation
- a mutation gate that stops before COM Name Arbiter reset or `PortName` writes unless all backups validate
- clearer technician-facing launcher text and field docs
- factored PowerShell functions for future posture, GUI, or platform changes
- an offline survey runner merge-drift repair that keeps the AutoFix contract test and current software-install harness contract test in the same runner

## Operator path

Fast apply path from the affected Cybernet repo root:

```cmd
Run-CybernetComPortAutoFix.cmd
```

Dry-run path:

```cmd
Run-CybernetComPortAutoFix-DryRun.cmd
```

The apply launcher runs the local script with `-Apply -Restart`. The dry-run launcher captures evidence and writes a mapping plan without applying changes or restarting.

## Safety boundaries

- Local Cybernet only.
- No remote execution.
- No admin-box target mutation.
- No SmartLynx or final app install.
- No USB/COM driver replacement.
- Default apply still stops unless the known COM3-COM6 pattern is present.
- No `-Force` validation or runtime proof was performed in this sprint.

## Registry-backup validation

The validation sprint found a bounded backup-path defect: native `reg.exe export` failures were not explicitly checked. PowerShell could therefore continue after a nonzero native exit code.

The AutoFix now requires every registry export to:

1. return native exit code `0`
2. create the expected `.reg` file
3. create a nonempty file

The successful backup result records:

```json
{
  "registry_backups": {
    "validated": true,
    "com_name_arbiter": "...\\COMNameArbiter-before.reg",
    "com_name_arbiter_size_bytes": 1,
    "device_parameters": [
      {
        "export_path": "...\\device-parameters-before-01.reg",
        "size_bytes": 1,
        "validated": true
      }
    ]
  }
}
```

The numeric sizes above are structural examples only. Runtime values come from the files produced on the Cybernet.

The static contract proves this order in the executable orchestration:

```text
registry backup call
  < backup validation gate
  < COM Name Arbiter reset
  < per-device PortName mutation
```

## Evidence output

AutoFix writes timestamped folders under:

```text
C:\Temp\CybernetCOM\autofix_YYYYMMDD_HHMMSS
```

An eligible dry run is expected to produce:

```text
COMNameArbiter-before.reg
device-parameters-before-01.reg
device-parameters-before-02.reg
device-parameters-before-03.reg
device-parameters-before-04.reg
autofix-summary.json
autofix-transcript.txt
```

`autofix-summary.json` records the validated registry backups and planned mapping.

Do not commit these runtime artifacts.

## Validation completed

Executed against an exact local reconstruction of the PR files:

```text
python Tests/survey/test_cybernet_com_autofix_contracts.py
PASS: 11 Cybernet COM AutoFix static contracts
```

Connector-side inspection also confirmed that the PR changed-file list contains no `.reg` exports, transcripts, screenshots, runtime logs, or machine-local evidence.

## Validation not completed in this environment

The execution environment was Linux-only and did not provide `powershell.exe`, Windows registry access, FINTEK/COM devices, or an affected Cybernet. Therefore these requested proofs remain pending on Windows:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$null = [scriptblock]::Create((Get-Content .\scripts\Invoke-CybernetComPortAutoFix.ps1 -Raw)); 'PARSE OK'"
Run-CybernetComPortAutoFix-DryRun.cmd
```

No real `C:\Temp\CybernetCOM\autofix_*` evidence folder was observed in this sprint, and no runtime `autofix-summary.json` result is claimed.

## Release hygiene

The branch had diverged after current `main` gained the software-install harness. The shared offline survey runner preserves both:

```text
Tests/survey/test_cybernet_com_autofix_contracts.py
Tests/survey/test_software_install_harness_contracts.py
```

The branch refresh uses a current-main integration branch and a normal pull-request merge into `feat/cybernet-com-port-autofix`; it does not force-push the feature branch.

## Next runtime decision

On a non-finalized Cybernet with the known COM3-COM6 state, run the PowerShell parse check and dry-run launcher. Inspect the newest evidence folder and confirm all five `.reg` files are nonempty and `autofix-summary.json` reports `registry_backups.validated` as `true`. Do not run apply or use `-Force` as part of this validation step.
