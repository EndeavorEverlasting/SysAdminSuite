# Windows Survey Runtime Troubleshooting

This note covers the first-run issues most likely to block the SysAdminSuite survey tools on a managed Windows workstation.

## Required local tools

- Git for Windows, including Git Bash
- Python 3
- Nmap with Npcap when approved network discovery is required
- A local clone of SysAdminSuite

## Use the Windows launchers

On Windows, prefer the `.cmd` launchers instead of calling the Bash scripts directly. The launchers prepare Git Bash and a working Python command before starting the corresponding script.

Examples:

```cmd
survey\sas-survey-targets.cmd --csv survey/input/combined_cybernet_neuron_manifest.csv --output survey/output/combined_targets_resolved.csv
```

```cmd
survey\sas-cybernet-xlsx-targets.cmd --workbook targets/local/example.xlsx --output survey/output/cybernet_targets.csv
```

```cmd
survey\sas-resolve-nmap-evidence.cmd --manifest survey/output/combined_targets_resolved.csv --nmap-output logs/nmap/example_discovery.xml --output survey/output/nmap_identity_resolver.csv --dashboard survey/output/nmap_identity_resolver.html
```

## Microsoft Store Python alias symptom

A common Windows symptom is:

```text
Python was not found; run without arguments to install from the Microsoft Store...
```

This can occur even when `python --version` works in Command Prompt. Git Bash may find a Microsoft Store `python3` alias before the installed Python runtime.

The Windows launchers call `survey\sas-windows-runtime.cmd`, which:

1. Locates Git Bash.
2. Validates `py -3`, `python`, or `python3` by actually importing Python.
3. Creates a temporary `python3` shim for Git Bash.
4. Prepends that shim to the launcher process PATH.

The shim is temporary and does not change the machine-wide PATH or execution policy.

## Local folders

Live target files and generated evidence stay local and must not be committed. Create these folders when needed:

```cmd
mkdir survey\input
mkdir survey\output
mkdir survey\artifacts
mkdir logs\network_context
mkdir logs\nmap
mkdir logs\targets
```

Expected local target files commonly include:

```text
survey/input/cybernet_survey_manifest.csv
survey/input/neuron_survey_manifest.csv
survey/input/combined_cybernet_neuron_manifest.csv
```

## Nmap DNS names versus tracker hostnames

Nmap may return a fully qualified DNS name such as:

```text
HOST001.example.internal
```

while a tracker manifest stores:

```text
HOST001
```

`sas-nmap-evidence-export.py` normalizes the observed hostname to the short computer name for matching and preserves the full DNS name in the Notes field. This prevents a false hostname-drift result.

## Handling rules

- Keep target CSVs, hostnames, IPs, MAC addresses, serials, and generated evidence out of Git.
- Do not broaden an approved network scope merely because a local adapter exposes a wider route.
- Resolve existing evidence before running additional checks.
- Treat hostname-only evidence as supporting evidence; the Cybernet serial remains the stable identity.
