# Cybernet one-target pilot

## Technician command

Use this surface for the first authorized Cybernet production target:

```powershell
& {
    $RepoRoot = '<SYSADMINSUITE-REPO-ROOT>'
    $CybernetFqdn = '<AUTHORIZED-CYBERNET-FQDN>'

    Set-Location -LiteralPath $RepoRoot
    git fetch --all --prune
    git switch main
    git pull --ff-only origin main
    .\Run-CybernetClientConfiguration.cmd Pilot $CybernetFqdn
}
```

Do not reconstruct the workflow from individual scripts. The root CMD owns the technician sequence.

## Eligibility gate

Proceed only when the assignment, inventory record, equipment label, and fully qualified DNS name all identify the same authorized **Cybernet clinical workstation**.

Never run this pilot against:

- a shared or normal user-login workstation;
- a Neuron;
- a tablet;
- a Kronos clock;
- another equipment profile;
- a target with unknown, ambiguous, or conflicting identity/profile evidence.

A serial number, hostname, MAC address, model, or successful probe is identity evidence; none of those alone authorizes the Cybernet profile. Stop on ambiguity.

## What the single Pilot command does

The launcher advances through bounded gates in this order:

1. **Deployment dry run** — validates the tracked Cybernet profile and six-package order without contacting the target or software share.
2. **Read-only live preflight** — tests only the authorized Kerberos SMB/Task Scheduler transport for the one FQDN.
3. **Harmless live certification** — creates one run-scoped noninteractive SYSTEM task, retrieves nonce-bound proof, and verifies task and staging teardown. It installs no software.
4. **Production confirmation** — pauses before higher-impact configuration. Read the target and action carefully.
5. **Production Apply** — configures and validates no-sleep, the physical power button, the integrated display Privacy/Menu and display power-button lock, and COM readiness; then installs the approved software set with AutoLogon last.
6. **Post-validation** — rechecks the Cybernet hardware profile without reinstalling software.

Any failed gate stops the pilot before the next higher-impact stage. Do not bypass or blindly retry a failed gate.

## Production profile applied

The tracked Cybernet profile requires:

- standby and hibernate set to Never on AC and DC;
- the Windows physical power button set to Do nothing;
- supported integrated-display Privacy/Menu and display power-button events disabled through MCCS VCP `0xCA = 0x0303`;
- COM readiness at `COM1, COM2, COM3, COM4`;
- the approved software installed in this exact order:
  1. Allscripts EEHR Shortcut UAI 2.2
  2. Epic Downtime Guide Shortcut 1.0
  3. Nuance Dragon Medical One 2025
  4. Hyland FOS Epic Integration 23.1.33.1000
  5. Epic BCA Web Shortcut 1.0
  6. NW AutoLogon Setup x64

AutoLogon must remain last. The pilot never reboots the target.

## Required completion result

The final launcher result must be:

```text
PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED
```

This proves the bounded automated pilot completed. It does not prove application behavior or post-reboot AutoLogon behavior.

Review generated evidence under:

```text
survey\output\runs\software-deployment-transport-*
survey\output\runs\software-deployment-transport-live-cert-*
survey\output\cybernet_hardware\client-configuration-*
```

Complete the generated `technician_software_acceptance.txt` checklist. Confirm every expected shortcut/application opens through the normal user workflow.

Record AutoLogon as installed only. Automatic sign-in may be claimed only after a separately authorized reboot and direct observation. Never place credentials, private lifecycle evidence, or target identifiers in Git.

## Stop conditions

Stop and escalate when:

- the target is not positively classified as Cybernet;
- Plan does not return `PLAN_READY`;
- preflight does not classify `kerberos_smb_task_ready`;
- harmless certification does not return `LIVE CERT PASS`;
- the launcher reports `ACTION_REQUIRED` or exits nonzero;
- hardware or COM validation fails;
- the software order differs from the tracked package set;
- AutoLogon would not be last;
- an unexpected reboot occurs;
- task or staging cleanup cannot be proven.
