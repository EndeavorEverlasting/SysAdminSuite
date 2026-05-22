# Bash-on-Windows Field Survey V1

## Purpose

Build the first working SysAdminSuite Bash-on-Windows field survey lane from current `origin/main`.

This lane converts the PR9 harvest concept into usable field tooling without collapsing the runtime doctrine.

## Runtime target

- Bash running on Windows, usually Git Bash or MSYS2.
- Bash scripts may call Windows-native executables.
- Expected Windows executables include:
  - `cmd.exe`
  - `hostname.exe`
  - `ping.exe`
  - `nslookup.exe`
  - `netsh.exe`

## Non-targets

- Do not treat Bash as Linux.
- Do not assume WSL.
- Do not assume macOS.
- Do not use Linux-only commands as defaults.
- Do not delete, truncate, or deprecate PowerShell files.

## First product slice

Create a small survey layer that can:

1. Confirm the Bash-on-Windows runtime.
2. Capture hostname.
3. Capture IP/network basics through Windows-native commands.
4. Capture DNS reachability.
5. Emit readable console output.
6. Later emit structured logs or CSV.

## First files expected

- `survey/sas-device-snapshot.sh`
- `survey/sas-neuron-environment.sh`
- `tests/bash/smoke-bash-windows-runtime.sh`
- `docs/COMMAND_CATALOG.md`
- `docs/AI_RUNTIME_CONTRACT.md`

## Safety posture

- Survey first.
- Report before mutation.
- No destructive action.
- No production branch mutation.
- Small commits only.
