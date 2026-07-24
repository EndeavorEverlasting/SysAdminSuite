# Portable On-Site Operator Runtime Fixes

## Field failures reproduced from operator evidence

The portable on-site surface must handle these field conditions without requiring username-specific path edits or unsafe target retries:

1. A single AutoLogon qualification request under `survey/input/autologon-system-qualification` must remain array-safe under PowerShell strict mode.
2. Windows 11 may return `unknown` from `netsh wlan show interfaces` even while the workstation is visibly connected to an approved Wi-Fi network. The network guard therefore falls back to the active `Get-NetConnectionProfile` Wi-Fi profile name before declaring posture inconclusive.
3. Network-gate actions accept both numeric and letter choices so an operator trained on numbered harness menus can use `1/2/3/Q` as well as `S/R/W/C`.

## Required field behavior

### AutoLogon request preparation

` sas autologon Prepare ` must:

- resolve the cached portable repo without username-specific path edits;
- treat zero, one, or many request files deterministically;
- create `qualification-request.local.json` from the tracked template when none exists;
- open the request for editing;
- perform no network activity or target mutation.

### Network detection

` sas network ` must:

1. attempt read-only SSID parsing from `netsh wlan show interfaces`;
2. if that yields `unknown`, inspect active Windows connection profiles read-only;
3. recognize a Wi-Fi profile whose name begins with the approved `NSLIJHS-WAB` prefix;
4. fail closed when neither approved Wi-Fi nor configured wired evidence is available.

Saved Wi-Fi profiles alone are never proof that the workstation is currently on that network.

### Guest / wrong-network choices

When approved posture is not detected, the operator receives:

```text
[1/S] Switch to a saved approved Northwell Wi-Fi profile
[2/R] I switched networks manually - recheck now
[3/W] Open Windows Wi-Fi settings, then recheck
[Q/C] Cancel this target operation
```

The saved-profile path still requires typing `SWITCH`. The gate never creates a Wi-Fi profile or stores credentials. Cancel remains before target contact or mutation.

## Proof boundary

Static and PowerShell regression tests cover the scalar-array bug, Windows connection-profile fallback, and numeric/letter menu contract. Actual recognition of a field workstation's active network remains live runtime proof and must be observed on the operator workstation before target execution.
