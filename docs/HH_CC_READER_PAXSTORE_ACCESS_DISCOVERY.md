# H&H CC Reader — PAXSTORE Access Discovery Evidence

Date: 2026-10-04
Status: P111 EVIDENCE SYNC — SANITIZED REPOSITORY LANE
Raw authority: private H&H Google Drive evidence workspace
Repository floor observed before branch: `main@a026d2d171c1730ccdd36c04ffc46392f2614dd1`

## Decision

The 2026-10-04 operator investigation reached and searched the **PAXSTORE App Store / application marketplace** and separately reached the **Global Developer Center**. Those surfaces are not equivalent to the documented PAXSTORE **Administrator Center**.

The current repository-safe evidence supports:

```text
AUTHENTICATED_PAXSTORE_SURFACE = APP_STORE
GLOBAL_DEVELOPER_ONBOARDING = OBSERVED
ADMINISTRATOR_CENTER_ENTITLEMENT = UNPROVEN
TERMINAL_MANAGEMENT_ENTITLEMENT = UNPROVEN
KIOSK4_CURRENT_FIRMWARE = UNOBSERVED
BASELINE_LOCKED = BLOCKED
```

Do not promote App Store search behavior into a claim that the account has no possible Administrator Center role. The evidence proves the surface reached and the results returned there.

## Captured evidence

Nineteen operator screenshots were ingested through the P111 evidence contract.

- Raw originals remain private in Drive and are bound by SHA-256.
- Public Git contains reviewed, cropped/redacted WebP derivatives only.
- Browser address bars/session-looking URLs, personal identity, entered contact/company data, and unrelated Cursor/desktop content were removed from tracked derivatives.
- Every derivative has a Photo ID plus raw/sanitized hashes in the evidence manifest.

Evidence directory:

`docs/evidence/hh-cc-reader/paxstore/2026-10-04/`

## What the captures establish

1. **Developer registration is a separate path.** The Global Developer flow requests company/business-registration information and a Business License/Certificate of Incorporation image.
2. **The authenticated portal surface reached is the App Store.** Its visible search control returns applications.
3. Searches were captured for `Terminal`, `BroadPOS`, `Center`, and `PAXSTORE`.
4. `Terminal Management` did not appear through the App Store application-search path.
5. `BroadPOS` produced BroadPOS-named applications rather than Administrator Center navigation.
6. `Center` produced five captured pages of application results.
7. The portal footer visibly exposes PAXSTORE support email `paxstore.support@pax.us`.
8. The captured footer build label is `v11.0.4_20260814180314`. This is preserved as **CAPTURED_UI_LABEL_ONLY**, not asserted as the official public release version.

## Public-document corroboration

PAX's Reseller Admin Guide describes the Administrator Center as a distinct portal with a grid selector and left-sidebar features including **Firmware List**, **Terminal Management**, **User Management**, and **Role Management**:

- https://faqs.pax.us/wp-content/uploads/2020/05/PAXSTORE-Reseller-Admin-Guide_v1.0.pdf

PAX's Role Management guide describes Terminal Management and Firmware List as role-controlled features and supports Full/Readonly access:

- https://faqs.pax.us/wp-content/uploads/2021/05/PAXSTORE-Role-Management-User-Guide-Reseller-V1.0_10-19-2020.pdf

The current PAX North America knowledge base exposes Terminal Management training material and an official public `PAXSTORE Release V 10.0` article:

- https://www.pax.us/paxstore-knowledge-base/
- https://www.pax.us/knowledge-base/paxstore-release/

The public documentation therefore corroborates the architectural distinction between **App Store** and **Administrator Center**, while the live screenshots prove which surface the operator actually reached.

## P111 proof semantics

### Captured fact

A value/UI element visibly present in an operator screenshot.

### External corroboration

A public PAX source independently describes product behavior, roles, support, or navigation.

### Inference

A reasoned interpretation that is not directly proven by the capture. Keep explicitly labeled.

### Unresolved

A required fact still absent from authoritative live evidence.

## Current proof ceiling

This packet does **not** prove:

- membership in the H&H/reseller estate that owns Kiosk4;
- absence of all Administrator Center entitlements;
- current firmware or installed application versions for serial `1240473751`;
- package mapping for `2.0.15.260522`;
- mutation authority;
- firmware/app deployment success.

## Next live transition

Continue the live lane, not generic marketplace search:

1. use the grid/portal selector or direct Administrator Center entry in one browser/session;
2. if Administrator Center is exposed, inspect Terminal Management / Firmware List read-only;
3. if it is not exposed, request **Readonly Terminal Management + Firmware List** on the estate that owns Kiosk4 or pivot to the authorized Experian/Payment Fusion management plane;
4. once a labeled Kiosk4 observation exists, run the existing Gate A freeze and require `OBSERVED + BASELINE_LOCKED`.

No firmware/app push is authorized by this evidence sprint.
