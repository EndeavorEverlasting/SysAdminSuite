# SAS AndroidProvider

The reusable provider owns runtime qualification, host readiness, device state,
private identity binding, inspection, transport leases and cleanup. PTop,
reference AdminBox and technician AdminBox use the same implementation, selected
by explicit node role. H&H retains firmware and workload interpretation.

## Technician front door

`Run-SasAndroidProvider.cmd` is the one tracked entrypoint. Its typed operations
are `status`, `doctor`, `prepare`, `verify`, `probe`, `inventory`, `tcpip-cert`,
and `last-result`. It never accepts arbitrary shell commands.

Use the repository-owned preparation/sealing workflow before protected-network
entry. The runtime source must pass canonical-development freshness or the
existing offline tracked-file seal. An isolated engineering worktree is only
eligible for synthetic fixtures, never operator device execution.

Preparation consumes a local official Google Windows Platform-Tools archive,
an independently approved archive SHA-256, and an explicit node role. Download
or obtain that archive before field entry. Preparation verifies every component,
records source/version/archive/component hashes and timestamp, and copies the
qualified bundle into the SAS-owned local cache. Runtime operations perform no
public downloads and never select SDK/PATH copies. Existing software-deployment
owners distribute assets; AndroidProvider is not another deployment engine.

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
one ready USB alias, and one device-derived IPv4 address. It rechecks readiness
and identity inside an exclusive host lease before changing transport. It
connects only to that exact address, proves stable identity over LAN, restores
USB, disconnects, verifies USB readiness, checks alias removal and requires an
observed connection refusal from the exact listener. A timeout or unreachable
network does not prove listener cleanup. Cleanup failure is `INCOMPLETE`.

A crash leaves the lease file for attended recovery. Do not delete it blindly:
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
