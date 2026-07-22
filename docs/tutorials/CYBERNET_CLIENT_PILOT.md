# Cybernet clickable live certification

## Technician action

1. Update the SysAdminSuite repository through the approved pull command supplied by the project lead.
2. Open the SysAdminSuite folder in File Explorer.
3. Double-click `Run-CybernetLiveCert.cmd`.
4. Enter the authorized short Cybernet hostname from the assignment or device label.

Do not derive, append, or type a DNS domain. The script resolves and validates one canonical FQDN from the approved controller's DNS context.

Do not reconstruct the workflow from individual PowerShell scripts. The root live-cert CMD owns the technician sequence, keeps the window open, and opens the generated handoff and evidence when the run stops or completes.

## Eligibility boundary

Use this surface only when the assignment, inventory record, and equipment label identify the target as an authorized **Cybernet clinical workstation**.

Never run it against:

- a shared or normal user-login workstation;
- a Neuron;
- a tablet;
- a Kronos clock;
- another equipment profile;
- a target with unknown, ambiguous, or conflicting identity/profile evidence.

A serial number, hostname, MAC address, model, successful DNS response, or reachable transport is identity evidence. None of those alone authorizes the Cybernet profile.

## What the CMD owns

The launcher performs these bounded gates in order:

1. **Controller network gate** — confirms the approved Northwell controller network posture.
2. **Canonical name gate** — accepts the short hostname, derives candidates from the controller DNS search context, and requires exactly one matching canonical FQDN. Zero matches, aliases to a different host, or multiple FQDNs stop the run.
3. **Deployment dry run** — validates the tracked Cybernet profile and approved six-package order without contacting the target or software share.
4. **Read-only live preflight** — checks only the selected Kerberos SMB/Task Scheduler transport for the resolved FQDN.
5. **Harmless live certification** — creates one run-scoped SYSTEM task, retrieves nonce-bound proof, and verifies task and staging teardown. It installs no software.
6. **Production confirmation** — pauses before higher-impact configuration.
7. **Production Apply** — applies and validates the Cybernet hardware profile, installs the approved package set with AutoLogon last, and produces technician acceptance evidence.
8. **Post-validation** — rechecks hardware without reinstalling software.

Any unresolved, ambiguous, or failed gate produces `ACTION_REQUIRED` and stops before the next higher-impact stage. Do not bypass or blindly retry it.

## Production profile

The tracked Cybernet profile applies:

- standby and hibernation set to Never on AC and DC;
- the Windows physical power button set to Do nothing;
- supported integrated-display Privacy/Menu and display power-button events disabled through MCCS VCP `0xCA = 0x0303`;
- COM readiness at `COM1, COM2, COM3, COM4`;
- the approved software in this exact order:
  1. Allscripts EEHR Shortcut UAI 2.2
  2. Epic Downtime Guide Shortcut 1.0
  3. Nuance Dragon Medical One 2025
  4. Hyland FOS Epic Integration 23.1.33.1000
  5. Epic BCA Web Shortcut 1.0
  6. NW AutoLogon Setup x64

AutoLogon must remain last. The launcher never reboots the target.

## Results

The CMD opens:

```text
survey\output\cybernet_live_cert\cybernet-live-cert-*\OPEN-ME-CYBERNET-LIVE-CERT.txt
```

The required completed automated status is:

```text
PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED
```

That status proves the bounded automated path completed. It does not prove application behavior or post-reboot AutoLogon behavior.

Complete the generated `technician_software_acceptance.txt`. Record AutoLogon as installed only. Automatic sign-in may be claimed only after a separately authorized reboot and direct observation.
