# SAS AndroidProvider

The reusable provider owns runtime qualification, host readiness, device state,
private identity binding, inspection, transport leases and cleanup. PTop,
reference AdminBox and technician AdminBox use the same implementation, selected
by explicit node role. H&H retains firmware and workload interpretation.

## Technician front door

`Run-SasAndroidProvider.cmd` is the one tracked entrypoint. Its typed operations
are `status`, `doctor`, `prepare`, `verify`, `probe`, `inventory`, `tcpip-cert`,
`stop-server`, and `last-result`. It never accepts arbitrary shell commands.
Doctor reports listener ownership and private server diagnostics. Stop-server
only stops a proven owned loopback server; it never kills a competing server.
Server version is reported from the owning qualified executable, with that
evidence basis explicit rather than represented as a separate wire-version probe.

Use the repository-owned preparation/sealing workflow before protected-network
entry. The runtime source must pass canonical-development freshness or the
existing offline tracked-file seal with `--expected-commit` bound to the selected
refreshed provider floor. Offline use verifies the same prepared commit and
required Android files without contacting GitHub. An isolated engineering worktree is only
eligible for synthetic fixtures, never operator device execution.

Preparation consumes a local official Google Windows Platform-Tools archive,
an independently approved archive SHA-256, and an explicit node role. Download
or obtain that archive before field entry. Preparation verifies every component,
records source/version/archive/component hashes and timestamp, and copies the
qualified bundle into the SAS-owned local cache. Runtime operations perform no
public downloads and never select SDK/PATH copies. Existing software-deployment
owners distribute assets; AndroidProvider is not another deployment engine.

Preparation also creates the sibling `android-platform-tools.qualification.json`
attestation, binding the approved archive digest to the complete manifest bytes.
Distribution and attended rollback preserve that attestation with its matching
bundle; an older unanchored runtime must be prepared again. Replacing executable
and manifest together cannot replace this independent preparation record.
The local host and attestation storage remain trusted: this does not protect
against an attacker able to rewrite both the runtime and its independent anchor.

Node configuration lives beside the owned runtime as `android-node.json`.
Supported roles are `ptop_lab`, `adminbox_reference`, and
`technician_adminbox_field`; hostname and LAN position never infer a role.
The previous runtime is retained as `.previous` for attended rollback; another
preparation stops if that backup has not been reviewed. Keys are never packaged.

## Identity and inspection

Probe reports no-device, USB-without-ADB, unauthorized, offline, ready,
multiple-device and unsupported states. Inventory requires an operator-local
JSON mapping of expected property names to values, including `ro.serialno` or
`ro.boot.serialno`. Include expected vendor/manufacturer properties where known.
ADB serials and TCP endpoints remain transport aliases. Stable property evidence
collapses USB/TCP aliases; mismatched, duplicated or unready aliases block.

Inventory covers properties, packages, processes, addresses, routes, connectivity
and device policy. Raw output stays in ignored private receipts under
`survey/output/android-provider/`; stdout prints only outcome and receipt path.
Do not place an identity file, runtime bundle, keys or receipts in Git.

## Network certification and recovery

TCP certification requires explicit transport authorization, bound identity,
and a separate private `--profile-file` approved by the operator. Its schema is
`sas-android-target-profile/v1`: `organization`, `site`, and `equipment` objects
each contain a nonempty `id`, `status: RESOLVED`, and `evidence_ref`; `site`
also contains `organization_id` matching the organization, `equipment` contains
`device_class: android`, and `allowed_operations` is exactly `["tcpip-cert"]`.
The top-level and nested objects must contain only the listed keys; additional
keys or operations are rejected.
These are explicit approved profile authorities, not profiles inferred from
device properties, hostname, LAN position, or the node role. Missing, unknown,
conflicting or unsupported authorities block transport mutation. Keep this file
private alongside the identity packet; never reuse another site's approval.
Certification also requires
one ready USB alias, and one device-derived IPv4 address. It rechecks readiness
and identity inside an exclusive host lease before changing transport. It
connects only to that exact address, proves stable identity over LAN, restores
USB, disconnects, verifies USB readiness, checks alias removal and requires an
observed connection refusal from the exact listener. A timeout or unreachable
network does not prove listener cleanup. Cleanup failure is `INCOMPLETE`.

A machine-wide lease and transport journal live under
`%ProgramData%/SysAdminSuite/android-provider/`; each account must be admitted to
that directory by workstation provisioning. Permission failure blocks execution.
An unresolved journal blocks later transport transactions. A crash leaves the lease file for attended recovery. Do not delete it blindly:
prove the recorded process has ended and inspect the device transport/cleanup
state first. Firmware, apps, reboot, debugging enablement and privilege changes
remain outside this provider's authority. Same-LAN presence is not permission.

H&H front doors remain compatible. Automatic network transitions are now gated
by `--authorize-transport`; H&H identity interpretation stays in its adapter.
Legacy `--allow-install` cannot acquire an unqualified runtime. Remote view is
optional through the existing H&H front door; process survival is not claimed
as frame/stream proof.

## Validation and proof

`Tests/survey/test_android_provider_implementation.py` exercises qualified offline
roles, corrupt/missing assets, hostile archives, identity ambiguity, contention,
partial mutation and failed cleanup. Existing H&H fixture contracts protect
workload classification. Synthetic launcher execution proves CMD composition,
not physical USB, LAN, AdminBox readiness, field acceptance or production.
