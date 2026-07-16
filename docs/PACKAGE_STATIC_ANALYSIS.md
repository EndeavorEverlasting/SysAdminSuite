# Package Static Analysis

SysAdminSuite can inspect large local application packages without uploading them and without executing package code.

## What it analyzes

The first release supports bounded inspection of:

- EXE and DLL PE headers;
- MSI, MST, MSP, and other OLE compound-file headers;
- ZIP-family archive member metadata without extraction;
- PowerShell, CMD, BAT, JavaScript, VBScript, shell, Python, XML, JSON, INI, INF, REG, and related text/configuration files;
- hashes, sizes, file classes, bounded entropy, mutation indicators, endpoint fingerprints, and optional parser enrichments.

The core analyzer uses only the Python standard library. When an approved offline wheelhouse is supplied, an isolated virtual environment may additionally load `pefile` and `olefile` for deeper PE and compound-file structure.

## What it never does

- execute installers, scripts, custom actions, or embedded payloads;
- follow shortcuts;
- extract archives;
- contact URLs, UNC paths, hosts, package shares, or targets;
- validate runtime behavior;
- write outside the selected evidence directory and optional repository-local virtual environment;
- print raw endpoint or secret-like strings.

## Windows quick start

From the repository root:

```powershell
.\scripts\Invoke-SasPackageStaticAnalysis.ps1 `
  -InputPath 'D:\PrivatePackages\Allscripts' `
  -CreateVenv
```

The default evidence root is:

```text
survey/output/package_static_analysis/<timestamp>/
```

The wrapper creates `.venv/package-analysis` when requested and runs the dependency-free analyzer. It does not download packages or Python modules.

### Optional offline enrichment

Prepare an approved local wheelhouse containing the packages listed in:

```text
tools/package-analysis/requirements-optional.txt
```

Then run:

```powershell
.\scripts\Invoke-SasPackageStaticAnalysis.ps1 `
  -InputPath 'D:\PrivatePackages\Allscripts' `
  -CreateVenv `
  -OfflineWheelhouse 'D:\ApprovedWheelhouse'
```

The wrapper uses `pip --no-index --find-links`. It will not fall back to the public package index.

## Bash quick start

```bash
bash scripts/invoke-sas-package-static-analysis.sh \
  --input /private/packages/allscripts \
  --create-venv
```

Optional wheelhouse:

```bash
bash scripts/invoke-sas-package-static-analysis.sh \
  --input /private/packages/allscripts \
  --create-venv \
  --offline-wheelhouse /private/wheelhouse
```

## Artifacts

- `package_analysis.json` — schema-backed file inventory, indicators, parser availability, errors, and proof flags.
- `package_analysis.txt` — concise English summary.

The JSON deliberately does not contain the absolute input path, raw extracted strings, private URLs, or UNC paths. Endpoint-like values are represented only by SHA-256 fingerprints.

## How to interpret the result

Static findings support package intake and harness design. They may identify likely:

- registry or service changes;
- scheduled tasks;
- reboot signals;
- AutoLogon or credential-provider behavior;
- browser policy;
- drivers;
- firewall or Group Policy changes;
- process execution;
- download or network code;
- secret-like configuration material.

An indicator means the bounded content scan observed related text or binary strings. It does not prove that the behavior runs in every installer path.

## Promotion into VM testing

A package should move into a disposable-VM lane only after:

1. every package component has an approved hash;
2. wrapper, transform, and configuration relationships are understood;
3. required optional static parsers have been run or explicitly skipped;
4. likely mutation classes are represented in the package behavior profile;
5. preflight, logs, runtime acceptance, reboot, and rollback checks are defined;
6. private endpoints and activation values are stored only in ignored operator-local configuration;
7. AutoLogon is excluded from the application VM sequence.

## Proof ceiling

The analyzer provides static-only evidence. A green result does not prove Authenticode trust, silent arguments, installation success, application launch, service health, reboot behavior, rollback, Epic integration, SSO, or physical Cybernet compatibility.
