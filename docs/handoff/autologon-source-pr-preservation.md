# AutoLogon Source PR Preservation Ledger

## Summary

This ledger records the final disposition of stale AutoLogon, software-acceptance, host-eligibility, and package-intake source PRs evaluated against the current main floor after PRs #253, #254, #255, #257, #258, and #259.

The preservation rule is selective: retain unique safe behavior, tests, and evidence contracts; reject stale duplicate transports, unsafe tutorial state, machine-local evidence, guessed installer arguments, and proof overclaims.

## Preservation ledger

| Source PR | Key surfaces | Preservation destination | Final disposition | Rejected or superseded portions |
|---|---|---|---|---|
| **#167** | AutoLogon state delta | Main via PR #193, frozen proof contracts in #253, canonical fixture coverage in #258 | Preserved; source may remain closed | Temporary diagnostic workflow and any readiness claim without password-presence evidence. |
| **#168** | AutoLogon deployment and runtime-proof entrypoints | Main via PR #193; canonical deployment via #255; deterministic routing via #257; composed fixture proof via #258 | Preserved; source may remain closed | Legacy direct WinRM deployment and any claim that deployment proves signed-in runtime behavior. |
| **#172** | AutoLogon assessment and software operator tutorial content | Current `docs/AUTOLOGON_ASSESSMENT.md`, `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md`, `START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md`, and PR #259 | Superseded after preservation; source may remain closed | Stale replacement of `START-HERE-SysAdminSuite.md` was removed because it broke the canonical dashboard/software-deployment documentation contract. |
| **#185** | Approved catalog, authorized manifest, and acceptance workflows | Main via PR #193; client acceptance composition via #259 | Preserved; source may remain closed | Stale configuration manifests replaced by the current approved catalog, request, proof-floor, and client-preference contracts. |
| **#188** | Core fail-closed host eligibility | Main via PR #193 | Preserved; source may remain closed | None for the core gate. Authorization remains a separate validated-request/final-gate responsibility. |
| **#189** | Read-only local package inventory | Main via PR #193; evidence-floor repair from #195 preserved by PR #256 | Preserved; source may remain closed | Machine-local default paths and inferred installer arguments. |
| **#191** | AutoLogon final-step gate and pilot checklist | Main via PR #193; transport convergence via #255; proof matrix via #258 | Preserved; source may remain closed | Direct legacy transport invocation and any automatic promotion from install success to runtime acceptance. |
| **#192** | Cybernet-specific host-eligibility extension | Core gate already on main; Cybernet explicit-target, one-pilot, maximum-25, client-preference, and mutation gates are enforced by #254 and #259 | Superseded; close after comment | Duplicate execution context and authorization model. Current main separates hostname eligibility, validated request authority, hardware/client target bounds, and runtime acceptance instead of combining them in one stale gate. |
| **#195** | Local package inventory evidence floor | Preserved in PR #256: redacted root identity, relative paths, null installer arguments without evidence, conservative classifications, sanitized fixtures, tests, and documentation | Preserved; source remains closed | None from the repaired evidence floor. |

## Proof-boundary closeout

1. `scripts/Invoke-SasCybernetDisplayButtonControl.ps1` remains the only repository authority for supported integrated-display button control. It probes MCCS support and readable VCP `0xCA`, applies `0x0303` only to eligible displays, verifies readback, and fails closed otherwise. No registry, BIOS, Device Manager, service, or unknown vendor-utility fallback is preserved.
2. PR #258 proves the canonical AutoLogon deployment chain only with a zero-network fixture and explicit simulated identity. It does not prove reboot, automatic sign-in, current-token access, application behavior, or operator acceptance.
3. PR #259 composes hardware configuration, the approved six-package software set, post-software hardware validation, and a separate technician acceptance checklist. Installer success cannot satisfy application or AutoLogon runtime acceptance.
4. The package-inventory lane remains read-only. It never approves or executes an installer, and it does not invent unattended arguments.
5. Live hostnames, usernames, OU paths, credentials, package paths, and raw runtime evidence remain operator-local and untracked.

## Closure rule

A source PR is closed only when its useful work is present on current main, preserved by PR #256, replaced by a named current authority, or proven duplicate. Remote branches are retained; no branch deletion or force-push is authorized by this ledger.
