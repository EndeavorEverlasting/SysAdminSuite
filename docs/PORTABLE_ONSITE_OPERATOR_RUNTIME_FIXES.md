# Portable On-Site Operator Runtime Fixes

## Field failures reproduced from operator evidence

The portable on-site surface must handle these field conditions without requiring username-specific path edits or unsafe target retries:

1. A single AutoLogon qualification request under `survey/input/autologon-system-qualification` must remain array-safe under PowerShell strict mode.
2. Windows 11 may return `unknown` from `netsh wlan show interfaces` even while the workstation is visibly connected to an approved Wi-Fi network. The network guard therefore falls back to the active `Get-NetConnectionProfile` Wi-Fi/network label before declaring posture inconclusive.
3. Network-gate actions accept both numeric and letter choices so an operator trained on numbered harness menus can use `1/2/3/Q` as well as `S/R/W/C`.
4. A saved-profile switch can return success before WPA2-Enterprise authentication finishes. The field sequence observed was `NORTHWELL-GUEST` -> approved saved profile `NSLIJHS-WAB(WPA2)` -> `Identifying...` -> stable Windows network label `nslijhs.net`. The verifier must wait through the transient state and prove the network transition instead of treating the connection-request exit code as success.

## Required field behavior

### AutoLogon request preparation

`sas autologon Prepare` must:

- resolve the cached portable repo without username-specific path edits;
- treat zero, one, or many request files deterministically;
- create `qualification-request.local.json` from the tracked template when none exists;
- open the request for editing;
- perform no network activity or target mutation.

### Network detection

`sas network` must:

1. attempt read-only SSID parsing from `netsh wlan show interfaces`;
2. if that yields `unknown`, inspect active Windows connection profiles read-only;
3. recognize an explicitly observable approved Wi-Fi label whose name begins with the approved `NSLIJHS-WAB` prefix;
4. fail closed when neither approved Wi-Fi nor configured wired evidence is available.

A Windows connection-profile name such as `nslijhs.net` is a network label, not proof of the Wi-Fi SSID by itself. Saved Wi-Fi profiles alone are also never proof that the workstation is currently on that network.

### Confirmed saved-profile transition

When the operator chooses an approved saved profile and types `SWITCH`, the gate must:

1. capture the pre-switch network label;
2. submit the bounded `netsh wlan connect` request;
3. wait up to the configured verification timeout for enterprise authentication to settle;
4. accept direct observation of an approved Wi-Fi label when Windows exposes it; otherwise
5. require the active Wi-Fi connection profile to leave the prior stable network label and reach usable `Subnet`, `LocalNetwork`, or `Internet` connectivity;
6. trust that approved saved-profile transition only for the lifetime of the current gate process;
7. emit the transition evidence into the operator network-posture JSON.

If the machine remains on the previous network, remains in `Identifying...`, or never reaches usable connectivity, the gate stays blocked. It does not contact or mutate a target.

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

Static and PowerShell regression tests cover the scalar-array bug, Windows connection-profile fallback, numeric/letter menu contract, and saved-profile transition-verification contract. Actual recognition of the field workstation after a real WPA2-Enterprise switch remains live runtime proof and must be observed on the operator workstation before target execution.
