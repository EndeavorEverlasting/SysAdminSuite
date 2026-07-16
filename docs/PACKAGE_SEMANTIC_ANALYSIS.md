# Package Semantic Analysis

SysAdminSuite can compose its canonical static inventory with a second, hash-verified semantic pass. The sidecar helps translate package structure into concrete deployment-harness requirements without running the package.

## Why this is a separate sidecar

`package_analysis.json` remains the stable file-identity and structural evidence floor. The semantic sidecar:

1. reads that result;
2. rejects a non-static or unsupported base result;
3. re-hashes every local source file;
4. refuses enrichment when a source changed after the base scan;
5. adds bounded .NET, SAPIEN/PowerShell-host, MSI/MST/MSP, and wrapper classifications;
6. derives explicit preflight, logging, runtime-acceptance, reboot, rollback, and environment requirements.

This composition preserves the distinction between observed structure and inferred behavior.

## Canonical Windows command

```powershell
.\scripts\Invoke-SasPackageSemanticAnalysis.ps1 `
  -InputPath 'D:\PrivatePackages\Allscripts' `
  -CreateVenv
```

With an approved offline wheelhouse:

```powershell
.\scripts\Invoke-SasPackageSemanticAnalysis.ps1 `
  -InputPath 'D:\PrivatePackages\Allscripts' `
  -CreateVenv `
  -OfflineWheelhouse 'D:\ApprovedWheelhouse'
```

The wheelhouse remains optional. The core CLR parser and marker classifier use the Python standard library. `olefile` can add bounded compound-stream evidence; no dependency is downloaded from the public index.

## Bash command

```bash
bash scripts/invoke-sas-package-semantic-analysis.sh \
  --input /private/packages/allscripts \
  --create-venv
```

## Artifacts

The composed run writes four files to one ignored evidence directory:

- `package_analysis.json`
- `package_analysis.txt`
- `package_semantic_analysis.json`
- `package_semantic_analysis.txt`

The semantic JSON is governed by `schemas/harness/package-semantic-analysis-result.schema.json`.

## Validation authority

`.github/workflows/package-static-analysis.yml` is the single cross-platform package-analysis CI gate. It runs both static and semantic executable contracts, validates both closed schemas, parses both PowerShell entrypoints on Windows, and checks both Bash entrypoints on Ubuntu. A separate semantic-only workflow is intentionally not maintained because duplicate gates can drift.

## Managed .NET evidence

For PE files with a CLR directory, the sidecar reports:

- CLI-header presence;
- CLR metadata-root presence;
- bounded runtime metadata version;
- IL-only, architecture, strong-name, and native-entrypoint flag presence;
- managed resource-directory presence;
- vtable-fixup presence.

A strong-name table or flag is not publisher trust. The sidecar does not verify Authenticode, strong-name validity, assembly behavior, or runtime compatibility.

## SAPIEN and packaged PowerShell evidence

When bounded binary markers jointly indicate SAPIEN packaging and PowerShell hosting, the result adds:

- `sapien_powershell_host`
- `powershell_host_material`
- `may_host_embedded_powershell`

These are static classifications. They do not prove which embedded script runs, what parameters are accepted, or whether the wrapper reports success correctly. A deeper future lane may decode a packaged script payload only when it can do so without execution and without exposing secrets.

## MSI, MSP, and MST evidence

The sidecar identifies the extension role and bounded table markers such as:

- `CustomAction`
- `ServiceInstall` and `ServiceControl`
- `Registry`
- `Binary`
- `Property`
- `Feature`
- `InstallExecuteSequence`

Raw compound-stream names are never emitted. `tables_decoded=false` remains explicit because marker or stream-name presence is not a decoded MSI database or proof that a custom action executes.

An MSI and MST used together must be represented as one package identity with both hashes. Transform-selected features still require a dedicated table-decoding or authorized VM proof lane.

## Generated harness requirements

The sidecar creates closed requirement groups:

- `preflight`
- `logging`
- `runtime_acceptance`
- `reboot`
- `rollback`
- `environment`

Examples include:

- verify every package hash;
- verify publisher trust separately;
- capture installed product, service, registry, task, driver, browser-policy, and firewall baselines when indicated;
- capture real process exit codes and vendor logs;
- enable verbose MSI logging;
- classify MSI exit codes `3010` and `1641`;
- observe services or managed processes for bounded stability;
- preserve shared prerequisites during rollback;
- use one package per clean disposable snapshot;
- keep AutoLogon outside the application VM lane.

These requirements are inputs to package behavior profiles and VM journeys. They are not proof that the package performs every inferred action.

## Fail-closed conditions

The semantic pass fails or records an error when:

- the base schema is unsupported;
- a base proof flag claims execution, mutation, network, trust, or runtime proof;
- the absolute-path boundary is not preserved;
- a source file is missing;
- a source hash changed after the base scan;
- a base relative path escapes the selected input root;
- a symlink would be followed;
- configured file or byte limits are exceeded.

## Proof ceiling

The highest proof is `static_semantic_inference`. No EXE, MSI, script, custom action, embedded payload, service, application, browser, driver, endpoint, VM, or Cybernet is executed or contacted. Every behavior inference requires later disposable-VM or authorized physical-device confirmation.
