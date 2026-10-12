# P95 — Android Platform-Tools archive trust bridge

## Status

**Accepted (architecture boundary).** Implementation belongs to P07/W2. No archive digest is approved by this document.

**Parent:** [SysAdminSuite #534](https://github.com/EndeavorEverlasting/SysAdminSuite/issues/534) · **Direction:** [P141 comment](https://github.com/EndeavorEverlasting/SysAdminSuite/issues/534#issuecomment-6130738526) · **Handoff:** `docs/handoff/android-adminbox1-autonomous-bootstrap-trustbridge-p04-20261012.md`

**Repo floor at decision:** `main@41d08db1bb86e3995d5530ec30ffe540654f9de8`

## Problem

Admin Box autonomous bootstrap can stage an official Google Windows Platform-Tools ZIP via `Config/Fetch-Installers.ps1`, but SAS provider qualification stops at `verify` with `QUALIFICATION_AUTHORITY_REQUIRED` because nothing supplies an **independently approved** archive SHA-256 into `prepare_bundle`. Post-download checksums and WinGet-published hashes are useful evidence; they are not organizational approval.

## End-to-end trust trace (current and target)

```text
[Independent approval]     configs/…/sas-platform-tools-archive-pins.json (NEW catalog; empty/disabled until reviewed pin)
        │
        ▼
[P07 resolver]             Resolve approved pin for artifact_id + node role (read-only until pin exists)
        │
        ▼
[Acquisition]                Config/Fetch-Installers.ps1 → version-specific dl.google.com URL from pin (NOT mutable latest)
        │
        ▼
[Byte continuity]          SHA-256(local file) == pin.expected_archive_sha256  else HASH_MISMATCH / ARCHIVE_HASH_MISMATCH
        │
        ▼
[Source admission]           android_provider_cli.admit_source(--expected-commit)  (unchanged seal/freshness gates)
        │
        ▼
[Preparation]                prepare_bundle(archive, expected_sha256)  (unchanged hostile-archive + rollback rules)
        │
        ▼
[Attestation]                android-platform-tools.qualification.json binds archive + manifest hashes (unchanged)
        │
        ▼
[Offline runtime]          verify_bundle(require_attestation=True) on status/doctor/verify (unchanged)
```

**Current broken seam:** `scripts/Invoke-SasAndroidToolchain.ps1` builds a fetch-map pointing at `platform-tools-latest-windows.zip`, fetches once, then calls `android_provider_cli.py verify` only. `Fetch-Installers.ps1` writes `checksums/*.sha256` **after** download. `prepare_bundle` never runs because `--archive-sha256` has no approved authority.

**Provenance bug (P07 must fix, not weaken verify):** `harness/api/android_provider.py` sets manifest `source` to the constant `PLATFORM_TOOLS_SOURCE` (`…/platform-tools-latest-windows.zip`) even when bytes came from a version-specific URL. After P07, manifest `source` MUST equal the pin’s `acquisition_url` (immutable), while `verify_bundle` MUST accept that pinned URL instead of only the mutable-latest constant.

## Candidate trust roots compared and falsified

| Candidate | What it claims | Falsification | Disposition |
| --- | --- | --- | --- |
| **(a) Repo/org immutable pin metadata** | A reviewed catalog entry binds `artifact_id`, version-specific Google URL, exact archive SHA-256, `approval_reference`, optional role scope, and promotion state **before** any prepare | Not falsified as a *model*. **Falsified as “already satisfied”:** no SAS Platform-Tools pin exists in `configs/software-packages/approved-apps.json` (Cybernet lane only; no Google Platform-Tools entry) and no dedicated provider pin file exists yet. | **SELECTED** |
| **(b) Policy-authorized WinGet version manifest alone** | e.g. `microsoft/winget-pkgs` `Google.PlatformTools` 37.0.1 installer YAML: `InstallerUrl` → `platform-tools_r37.0.1-win.zip`, `InstallerSha256` published | **Falsified as independent approval:** community manifest hash is third-party metadata, not org sign-off; manifest revision is not bound to SAS change control; WinGet nested/portable layout ≠ SAS “complete official archive” contract without explicit pin; trusting manifest SHA without a reviewed repo pin repeats “hash of download = approval”. Organizational *acceptance of WinGet as channel* is unproven in repo policy. | **REJECTED as trust root** (may be cited only inside a pin’s `acquisition_evidence` after (a) approves) |
| **(c) Approved offline archive manifest (share checksum sidecar)** | `Fetch-Installers.ps1` / software-repo `checksums/<file>.sha256` beside staged installers | **Falsified as independent approval:** digest is computed from the same retrieval pipeline it is meant to approve (circular); toolchain currently pins **mutable** `latest` URL so checksum does not bind version; sidecar has no `approval_reference`, role binding, or SAS qualification semantics; opaque ZIP remains blocked from `Invoke-SasPackageTrust.ps1` VM lane. | **REJECTED as trust root** (checksum sidecar remains post-fetch **continuity** check only) |

## Selected contract — exactly one

**Contract (a): `sas-platform-tools-archive-pins/v1` — tracked immutable archive pin catalog owned by the Android provider qualification lane.**

This is intentionally **not** `configs/software-packages/approved-apps.json` (Cybernet deployment catalog) and **not** `Invoke-SasPackageTrust.ps1` (opaque ZIP / VM intake). It reuses the **same organizational pattern** as `credentialed_winrm_requires_independently_pinned_sha256`: no live qualification until a human-reviewed digest and reference are committed.

### Owner and surfaces

| Concern | Owner |
| --- | --- |
| Pin schema + catalog file | **P07** adds `schemas/harness/sas-platform-tools-archive-pins.schema.json` and `configs/android-provider/sas-platform-tools-archive-pins.json` (initially no enabled pin or `promotion_status: blocked_pending_independent_sha256_pin`) |
| Pin resolution (read-only) | **New** `harness/api/android_platform_tools_pin.py` — pure JSON load + fail-closed validation; no network |
| Orchestration | **Existing** `scripts/Invoke-SasAndroidToolchain.ps1` Bootstrap/Repair path (W2); **existing** `Config/Fetch-Installers.ps1` for bytes |
| Qualification | **Unchanged** `prepare_bundle` / `verify_bundle` / attestation semantics in `harness/api/android_provider.py` |
| Operator entry | **Existing** `Run-SasAndroidProvider.cmd` → `android_provider_cli.py prepare` with resolver-supplied `--archive` and `--archive-sha256` |

### Pin record shape (normative for P07)

Each enabled pin MUST include at minimum:

- `artifact_id`: `android-platform-tools-windows` (matches `harness/api/sas-android-provider-boundary.v1.json`)
- `acquisition_url`: immutable Google version-specific HTTPS URL (reject `platform-tools-latest-windows.zip` in pins)
- `expected_archive_sha256`: 64-char lowercase hex from **independent review**, not from agent observation alone
- `approval_reference`: non-empty ticket/review id (same discipline as package trust policy)
- `allowed_node_roles`: subset of `ptop_lab` | `adminbox_reference` | `technician_adminbox_field`
- `promotion_status`: `approved_for_provider_prepare` | `blocked_pending_independent_sha256_pin`
- Optional `acquisition_evidence`: sanitized pointer (e.g. WinGet manifest path + commit) — **informational**, never sufficient without (a)

Pins MUST NOT contain host paths, serials, keys, or private profile data.

### Bridge into `prepare_bundle` (call stack)

```text
Manage-AdminBoxAndroidToolchain.cmd Bootstrap   (P07 registered verb)
  → scripts/Invoke-SasAndroidToolchain.ps1
      → android_platform_tools_pin.resolve(artifact_id, node_role)
           → INDEPENDENT_APPROVAL_REQUIRED | QUALIFICATION_AUTHORITY_REQUIRED if no approved pin
      → build Fetch-Installers job from pin.acquisition_url (version-specific filename)
      → Config/Fetch-Installers.ps1 -RepoRoot <staging> …
      → assert Get-FileHash(staged) == pin.expected_archive_sha256
      → android_provider_cli.py prepare
           --role <NodeRole>
           --archive <staged zip>
           --archive-sha256 <pin.expected_archive_sha256>
           --expected-commit <selected refreshed commit>
      → prepare_bundle(archive, expected_sha256)   # harness/api/android_provider.py
      → android_provider_cli.py verify/status/doctor (same commit)
```

**Hard rule:** The value passed to `prepare_bundle` as `expected_sha256` MUST originate from the pin catalog, never from `Fetch-Installers` output alone and never from WinGet YAML alone.

### Typed gates (receipts / reason codes)

| Code | Meaning |
| --- | --- |
| `QUALIFICATION_AUTHORITY_REQUIRED` | No enabled pin / promotion blocked (current production state) |
| `INDEPENDENT_APPROVAL_REQUIRED` | Pin file missing entry or `approval_reference` empty |
| `SOURCE_POLICY_DENIED` | URL host not allow-listed or pin URL is mutable-latest |
| `HASH_MISMATCH` / `ARCHIVE_HASH_MISMATCH` | Staged bytes ≠ pin |
| `PREPARED` / `VERIFIED` | Successful prepare + verify with attestation (P07 receipts) |

Existing provider codes (`UNSAFE_ARCHIVE_ENTRY`, `PRIOR_RUNTIME_BACKUP_REQUIRES_REVIEW`, source admission failures) remain unchanged.

### Negative tests (W1-C / P07 acceptance)

Synthetic and fixture-only; no live Google fetch required for most cases:

1. Empty catalog → resolver returns `QUALIFICATION_AUTHORITY_REQUIRED`; prepare not invoked.
2. Pin with `promotion_status: blocked_pending_independent_sha256_pin` → same.
3. Pin URL uses `platform-tools-latest-windows.zip` → schema/validator rejection or `SOURCE_POLICY_DENIED`.
4. Staged file hash ≠ pin → `HASH_MISMATCH` before CLI prepare.
5. Correct hash but truncated ZIP / traversal / duplicate `adb.exe` → `prepare_bundle` raises `UNSAFE_ARCHIVE_ENTRY` (existing tests extended).
6. WinGet manifest SHA used without catalog pin → resolver refuses (`INDEPENDENT_APPROVAL_REQUIRED`).
7. Fetch-Installers `.sha256` sidecar only → does not enable prepare.
8. SDK `platform-tools/adb.exe` on PATH → `resolve_host` reports competing runtime; still no prepare via SDK copy.
9. Role `adminbox_reference` with pin limited to `ptop_lab` → blocked.
10. `--expected-commit` mismatch with admitted source → source admission fails before prepare.
11. Interrupted fetch (partial `.part`) → no prepare; prior qualified bundle preserved.
12. Stale pin (future: optional `supersedes` / version bump) → old hash rejected after org updates pin.

### Privacy proof

- Catalog and schema live in public Git; they contain only vendor URLs, public version strings, hashes, and review ticket ids.
- Host-specific receipts stay under ignored `survey/output/android-provider/` and `survey/output/android-toolchain/` (existing rule).
- Resolver and pin loader perform no network I/O and emit no absolute operator paths in stdout (CLI already types failures).

### Revocation / update strategy

- Org approves a **new pin row** (new version URL + SHA-256 + reference); prior pin `promotion_status` set to `superseded` (P07 schema).
- Hosts with qualified runtime keep attestation until operator runs attended prepare with new pin; rollback `.previous` rules unchanged.
- WinGet manifest updates without a matching repo pin MUST NOT auto-qualify hosts.

## Current operational state

**`APPROVAL_AUTHORITY_REQUIRED`** — repository search confirms:

- No Google Platform-Tools entry in `configs/software-packages/approved-apps.json`.
- No `configs/android-provider/sas-platform-tools-archive-pins.json` (to be added in P07, empty/blocked).
- Toolchain still stages mutable latest URL (`Invoke-SasAndroidToolchain.ps1` lines ~200–208).

### Evidence packet for human approver (prefill only — not approval)

Use this checklist to create the first pin; **do not commit a hash until independent review completes:**

| Field | Candidate source for reviewers (not auto-trusted) |
| --- | --- |
| Version | e.g. `37.0.1` from Google `Pkg.Revision` / versioned ZIP naming |
| `acquisition_url` | e.g. `https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip` (WinGet 37.0.1 installer manifest cites this URL; verify against Google release policy) |
| `expected_archive_sha256` | Must be verified offline by approver against **their** downloaded bytes; WinGet publishes `45F4D63113E895EBDE0C90F194099A4676B6AC653BD28D54314A9E022BBC1A99` for 37.0.1 — **candidate only** until ticketed review |
| `approval_reference` | Empty until security/package owner assigns id |
| Complete ZIP | Must contain required components per `REQUIRED_COMPONENTS` in `android_provider.py` |

## Proof ceiling

This decision document proves **architecture traceability and contract selection** from existing code and docs only. It does **not** prove: an approved digest exists, Admin Box Apply, live fetch, `prepare` success, device ADB, or online revocation of Google artifacts.

## P07 non-goals

- No second downloader; reuse `Fetch-Installers.ps1`.
- No SDK/PATH ADB as SAS fallback.
- No self-approval in CI or agent commits of `expected_archive_sha256`.
- No conflation with `Invoke-SasPackageTrust.ps1` production/VM disposition.
- No device/firmware/network ADB mutation in the trust-bridge lane.

## References

- `docs/ANDROID_PROVIDER.md` — independent archive SHA and attestation
- `docs/PACKAGE_TRUST_VERIFICATION.md` — opaque ZIP / offline Authenticode ceiling
- `docs/ANDROID_TOOLCHAIN_PROVISIONING.md` — `QUALIFICATION_AUTHORITY_REQUIRED`
- `harness/api/android_provider.py` — `prepare_bundle`, `verify_bundle`, `PLATFORM_TOOLS_SOURCE`
- `harness/api/android_provider_cli.py` — prepare inputs and source admission
- `Config/Fetch-Installers.ps1` — post-download hash only
