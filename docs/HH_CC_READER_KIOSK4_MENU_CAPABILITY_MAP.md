# H&H CC Reader — Kiosk4 Menu Capability Map

Date: 2026-10-04  
Status: P13/P111 RECTIFICATION — SANITIZED REPOSITORY DERIVATIVE  
Source authority: private H&H Google Drive operator evidence and current-conversation photos  
Repository: `EndeavorEverlasting/SysAdminSuite`  
Mutation authority: `false`

## Purpose

Preserve the completed local AxiaMed/Kiosk4 menu crawl so future agents do not ask the operator to repeat exhausted options.

This document is a sanitized derivative. It intentionally excludes credentials, live serial/MAC/IP values, session-bearing URLs, private Drive file IDs, and raw credential-bearing screenshots.

## Evidence boundary

| Evidence | Disposition | Repository rule |
| --- | --- | --- |
| First admin-unlock prompt photo | `PRIVATE / DO-NOT-SYNC` | Credential-bearing; may only be referenced as proof of numeric admin entry after redaction. |
| Numeric prompt with USB keyboard digits | `PRESENTATION_SAFE_DERIVATIVE_ALLOWED` | Proves keyboard digits register in numeric credential fields. |
| Ping Test host-name text photo | `PRESENTATION_SAFE_DERIVATIVE_ALLOWED` | Proves alphanumeric text can enter diagnostic host-name fields via USB keyboard. |
| Burger-menu inventory photo | `PRESENTATION_SAFE_DERIVATIVE_ALLOWED` | Proves visible local menu option list. |

## Capability taxonomy

| Local option / surface | Observed input behavior | State | Future action |
| --- | --- | --- | --- |
| Unlock Admin Menu | Numeric-only; physical keypad and USB keyboard digits work | `PROVEN_ADMIN_ENTRY` | Do not replay; keep credential evidence private. |
| Display Settings | Numeric second-layer credential gate; alpha rejected | `NUMERIC_CREDENTIAL_GATE` | Do not treat as keyboard failure. |
| Sound and Notifications | Numeric second-layer credential gate | `NUMERIC_CREDENTIAL_GATE` | Do not reopen without new evidence. |
| Connectivity Test | Previously exhausted and documented | `CLOSED_DO_NOT_REOPEN` | Do not repeat for timestamps. |
| Ping Test | Alphanumeric host-name field via wired USB keyboard | `ALPHANUMERIC_DIAGNOSTIC_FIELD` | May support technical bidirectionality evidence, not firmware proof by itself. |
| Run Test Transaction | Loads and returns to AxiaMed/default screen | `OBSERVED_NO_VERSION_SURFACE` | Not a firmware observation path. |
| Trace Route | Alphanumeric host-name field via wired USB keyboard | `ALPHANUMERIC_DIAGNOSTIC_FIELD` | Retain as diagnostic text-input proof. |
| Netstat | Thoroughly explored | `CLOSED_DO_NOT_REOPEN` | Do not reopen. |
| Diagnostic Test | Numeric credential gate | `NUMERIC_CREDENTIAL_GATE` | Do not treat as alpha-input branch. |
| Network Settings | Surface already exhausted | `CLOSED_DO_NOT_REOPEN` | Do not reopen. |
| Change Environment | Numeric credential gate | `NUMERIC_CREDENTIAL_GATE` | Requires authorized owner path; no guessing. |
| Reset Device | Numeric credential gate | `NUMERIC_CREDENTIAL_GATE / DO_NOT_USE_AS_FIRMWARE_PATH` | Do not use as firmware path. |
| Lock Admin Menu | Menu state action | `ADMIN_STATE_ACTION` | Not a firmware path. |

## P13 recurring-failure rule

Future agents must consume this capability map before proposing local field work.

Forbidden repeats unless new evidence invalidates this map:

- generic menu inventory crawl;
- Netstat replay;
- Connectivity Test replay;
- Network Settings replay;
- FUNC/ALPHA/tap/hold/simultaneous-key discovery;
- treating numeric credential fields as proof that the device cannot accept alphabetic input anywhere;
- asking the operator to re-prove that Ping Test and Trace Route accept host-name text.

## Technical interpretation

The device is not globally incapable of alphabetic input. It accepts alphanumeric text in diagnostic host-name fields when a wired USB keyboard is attached.

The numeric-only behavior is field-specific and appears to be enforced by the application/prompt configuration for credential-gated settings surfaces. This distinction must remain explicit in future presentation, repo, and field guidance.

## Firmware-program consequence

The local menu crawl is closed as a discovery branch. It remains valuable presentation evidence because it demonstrates disciplined narrowing of the firmware problem.

The firmware program remains open through authorized technical source branches:

1. Experian / AxiaMed Control Center;
2. provider or acquirer TMS / NTMS;
3. provider-managed automatic update;
4. PAXSTORE reseller / Administrator Center entitlement;
5. PAX Partner / PayDroid Tool as lab-only fallback;
6. package metadata from authorized support / merchant-services owner.

Public mirror / ROM absence remains a retained dead end, not proof that the authorized package does not exist.

## Presentation-safe deck claim

> We exhausted the local AxiaMed admin menu without mutating the reader. The terminal accepts alphanumeric input in diagnostic host-name fields, but credential-gated system areas are numeric-only under this application configuration. That closes menu-poking and moves the firmware program back to authorized management planes and package/version-domain evidence.

## Proof ceiling

This document proves only the sanitized menu/input taxonomy and local-branch closure record.

It does not prove:

- current firmware;
- version-domain binding;
- `BASELINE_LOCKED`;
- credential ownership;
- package/restore mapping;
- mutation authority;
- firmware deployment;
- post-deployment runtime behavior.
