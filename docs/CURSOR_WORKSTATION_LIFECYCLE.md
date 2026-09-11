# Cursor Workstation Lifecycle

## Current safety floor

This document is the progressive-disclosure authority for Cursor workstation diagnosis in SysAdminSuite. The current integrated candidate is deliberately **read-only**: `Audit` and `Verify` are implemented; `InstallSystem`, `Uninstall`, and `RecoveryPurge` are intentionally unavailable until the mutation trust boundary is hardened and separately proven.

This reduction is evidence-driven. The earlier lifecycle branch had unresolved review findings around custom profile-controlled deletion, wrong-user HKCU targeting after elevation, registry-controlled uninstaller execution, process ownership, unresolved path tokens, persisted PATH semantics, installer identity, run-directory collisions, and stale-checkout mutation. Read-only inventory is still useful and can be integrated without carrying those hazards forward.

## Canonical front door

```cmd
Manage-Cursor.cmd Audit
Manage-Cursor.cmd Verify -ExpectedState Absent
Manage-Cursor.cmd Verify -ExpectedState System
```

The launcher delegates only to `scripts/Invoke-SasCursorWorkstation.ps1`. Any other action fails closed with exit code 3.

The canonical profile is `Config/cursor-workstation-profile.json`. The engine does not accept a custom profile path. Runtime evidence is written only beneath `%LOCALAPPDATA%\SysAdminSuite\field-runs\cursor\<timestamp>-<guid>\cursor_workstation_result.json` and is not tracked.

## What Audit proves

`Audit` inventories, without application mutation:

- Cursor uninstall registrations whose display name matches the canonical profile;
- canonical machine and current-user install roots;
- whether the expected `Cursor.exe` exists under those roots;
- processes whose executable path is actually beneath a canonical Cursor root;
- `cursor` commands whose resolved path is beneath a canonical Cursor root;
- the current Windows security principal, SID, and profile path.

A command named `cursor` outside the canonical roots is recorded as ignored external evidence and does not make Cursor present. A process named `Cursor.exe` is not treated as Cursor-owned unless its executable path is under a canonical root.

If an environment token such as `{PROGRAMFILESX86}` is unavailable, that profile path is skipped rather than becoming an empty-rooted path.

## Verification semantics

`Verify -ExpectedState Absent` proves only **absent for the current security principal plus canonical machine roots**. It does not prove that another Windows user's HKCU/AppData is clean. The result status is therefore `VERIFIED_ABSENT_CURRENT_CONTEXT`, not a global absence claim.

`Verify -ExpectedState System` requires both:

1. at least one matching machine uninstall registration; and
2. the expected `Cursor.exe` beneath a canonical machine install root.

A stale or empty `%ProgramFiles%\Cursor` directory alone is insufficient. Concurrent user-scoped evidence prevents the `System` classification.

If process inspection fails, absence/system verification fails closed as `inspection-incomplete` rather than guessing.

## Incident doctrine preserved from the field case

Duplicate registrations, mixed `Cursor (User)` and machine installs, stale roots, or `unins000.dat` / Error 32 are local installation evidence. Audit those facts before expanding the hypothesis to a vendor outage. A clean local installation still does not prove vendor services are healthy.

This safety floor does **not** tell the operator to manually delete roots, registry keys, PATH entries, or user state. Those mutations remain quarantined until the next lifecycle sprint closes the required trust gates.

## Mutation gates that must be closed before install/uninstall/purge exists

A future mutating implementation must, at minimum:

1. execute only from a proven current canonical runtime;
2. bind the affected Windows user SID/profile before elevation and distinguish it from the administrator identity;
3. accept only the canonical immutable profile or enforce immutable allowlisted roots/predicates;
4. refuse unresolved environment tokens and prove every destructive path is contained by an approved Cursor root;
5. validate registered uninstall executables are contained in approved roots and have an approved publisher signature before elevation executes them;
6. stop only processes whose executable path proves Cursor ownership;
7. preserve `REG_EXPAND_SZ` semantics when rewriting PATH;
8. require a precise approved installer filename and signer identity, plus SHA-256 evidence;
9. treat nonzero uninstaller exit codes as failures;
10. export user state to a local ignored path before any explicit state purge;
11. use collision-resistant evidence run IDs; and
12. prove the full mutation path under focused contracts and Windows CI before field use.

## Proof ceiling

Repository/CI proof can establish profile/schema consistency, read-only routing, PowerShell parsing, current-context inventory behavior, and fail-closed verification semantics. It cannot prove a physical workstation repair, another user's profile state, GUI launch, login/session health, vendor-service health, or authorize software mutation.
