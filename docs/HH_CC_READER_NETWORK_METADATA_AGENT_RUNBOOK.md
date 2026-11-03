# H&H A80 network metadata observation — local AI agent execution contract

**Owner:** SysAdminSuite | **Scope:** authorized read-only PAX A80 firmware/software metadata | **Date:** 2026-11-03
**Agent objective:** Obtain the installed firmware version **on the existing identified terminal** and the shape/provenance of related OS, app, hardware, and management metadata. Identify how Admin Box communicates with it (direct LAN vs vendor management plane vs terminal-initiated vendor sessions). Supply evidence-bound facts to the separately owned BofA reply draft. **Do not update, roll back, flash, reset, log a transaction or select a target package.**

## Recovered technical floor — do not regress

- Physical product family **PAX A80**, healthcare payment application **Bank of America/AxiaMed**. Exact reader identity was already reconciled in the private H&H evidence store. Different private MACs were observed on different test terminals; keep those records separate.
- The A80's built-in **Connectivity Test listed PAX Store Push Service Primary (443)** along with payment, diagnostic, and terminal-management functions. Its **Netstat displayed active Internet connections (without server listeners)**. These are evidence that the reader can initiate network communication and has management/cloud-service candidates; they are **not** proof of a PAXSTORE tenant, enrolled account, IP endpoint, or inbound port 443.
- Previous scoped inbound reachability/port probes, menu crawl, keypad/HID experiments, USB-OTG/ADB enumeration, generic PAXSTORE marketplace account exploration and START TEST have already been performed. Do **not** start over merely to collect a new timestamp. The Admin Box USB OTG/ADB attempt failed at Windows enumeration on the tested configuration; this is not proof of no network-management capability.
- The representative Kiosk4 serial/MAC/IP are private records and may have changed network placement. Resolve the **current** exact target from its existing private receipt and approved network context. Never use a different terminal's IP, MAC or serial as the Kiosk4 profile.
- There is a manufacturer-documented Android 10 / PCI 6 A80 SKU family and a distinct older Android 6/7 / PCI 5 family. A SKU observed in another photo cannot be assigned to Kiosk4 without a same-device label or authorized management record.
- Vendor-provided **Taurus / PayDroid 6.0.1** and **Cedar / PayDroid 10** strings are candidate base-OS package families. `2.0.15.260522` is a vendor-described **PFT** example of unresolved component/domain, **not** a proved current/latest/approved device firmware version.
- Bank/vendor engineering advised that firmware rollback is unavailable; **rollback evaluation is out of this read-only investigation**, not a prerequisite to observing the installed version. Existing firmware-mutation policy remains intact for any separately approved future project.

## Critical architecture distinction

```text
                  Authorized enterprise / home-lab network
    Admin Box ------------ read-only identity ------------> A80
       |                      ARP/route/ICMP/TCP ONLY IF NEW PROOF IS NEEDED
       |
       +--- HTTPS / sanctioned provider API / UI ---> estate management record
                                                     | model / PN / osVersion
                                                     | installedFirmware.firmwareName
                                                     | installedApks versionName
                                                     | last reported check-in / provenance
                                                     v
                                            A80 initiates outbound sync
                                            (provider/PAXSTORE/TMS candidate)
       |
       +--- approved gateway / firewall / switch mirror ---> observed A80 egress,
                                 DNS/remote-IP/port/TLS metadata (not payloads)
```

A negative inbound TCP/443 probe only means **that one inbound probe did not find a listener**. It does not imply that cloud HTTPS is absent, the reader is offline, or that firmware metadata is inaccessible. Remote management commonly means **device-initiated outbound** traffic and **admin-to-cloud** inventory reads.

### Source precedence: first estate-specific truth, then supported fallbacks

| Lane | Authoritative route / existing tool | Output | If not accessible |
| --- | --- | --- | --- |
| **A: H&H management plane** | Authenticated **AxiaMed/Experian Control Center / Payment Fusion / IngEstate** terminal details. Use current org-approved account, **read-only**, no invented API endpoints. | Installed version with native field label; terminal registration, package/app version, last sync/check-in. | Mark `ESTATE_READ_ROLE_REQUIRED`. Continue B/C independently. |
| **B: PAXSTORE management API** | Authenticated **existing estate's** PAXSTORE Terminal Management OpenAPI **GET by serial** via existing `Observe-HHCCReaderPaxstoreTerminal.cmd`; not public Marketplace browsing. | `installedFirmware.firmwareName` and install time; optional `terminalDetail` PN/Android and `installedApks` separate app versions. | Mark `AUTHORIZED_ACCESS_SETUP_REQUIRED` if genuinely owned; otherwise `EXTERNAL_ENTITLEMENT_REQUIRED`. Ask vendor for read-only owner-mediated export, not a key by email. |
| **C: recorded device egress** | Previously captured AxiaMed Connectivity Test / Netstat; if a *new* approved network-placement question exists, source DHCP/firewall/DNS/ARP or switch SPAN/mirror **from the network authority**. | Exact observed source/destination/protocol and timestamps, plus hypotheses for management owner. | `EGRESS_METADATA_NOT_VISIBLE_AT_THIS_CAPTURE_POINT`, **not** `NO_COMMUNICATION`. Continue A/B. |
| **D: direct LAN observer** | Already available `Probe-HHCCReader.cmd IPV4 EXPECTED_MAC` only for a newly justified one-target placement/identity discriminator. | Adapter/IP/L2 neighbor/MAC/ICMP/single TCP-port receipt; **not** firmware. | `DIRECT_LAN_NOT_PROVING_MANAGEMENT_PROTOCOL`, not firmware failure; resume A/B. |

**Protocol selector:** `Select-HHCCReaderFirmwareProtocol.cmd CONTEXT_JSON`, using current P95 sanitized device/site signals; it dispatches an observation route and always returns `mutation_authorized=false`. Retain all plausible management branches instead of assuming POSLink, RS232, generic SNMP, Android ADB, HTTP/443 on the terminal, or another acquirer's TMS protocol. Never invent an IP endpoint, service login, or credentials.

## Agent execution — act now on recovered evidence

1. **Refresh/ground the local installation:** follow SysAdminSuite `AGENTS.md` repository-freshness gate and its sealed-runtime posture; never launch stale checkout scripts. Read `docs/HH_CC_READER_NETSTAT_BASELINE.md`, `docs/HH_CC_READER_FIRMWARE_OBSERVATION_PROGRAM.md`, `docs/HH_CC_READER_FIRMWARE_PROTOCOL_PORTFOLIO.md`, `docs/HH_CC_READER_HOME_LAB_WORKFLOW.md`, and `docs/HH_CC_READER_P5_READONLY_SESSION_RUNBOOK.md`. Recover already-closed branch receipts and exact private identity. Do not request operator recapture.
2. **Make an evidence inventory:** for each past observation, record source, date, reader identity binding, local-vs-cloud scope, native field label, raw value, and status. Mark `PAX Store Push Service Primary (443)` as `DEVICE_UI_SERVICE_CHECK` only, not an observed socket owner or direct management API. Keep historical 2026 campus/private-lab networks distinct.
3. **Select the best authorized read-only management surface:** run P95 selector after supplying actual evidence signals. Use any existing authorized Control Center/IngEstate read role first; capture terminal detail only. Do not turn absence of one entitlement into no-solution. If the operator already administers an enrolled PAXSTORE marketplace, ESI keys may be configured through that known owner; never solicit or log API keys.
4. **Run already implemented PAXSTORE GET adapter only if actual estate entitlement is verified:**

   ```bat
   Observe-HHCCReaderPaxstoreTerminal.cmd --serial PRIVATE_APPROVED_SERIAL --expected-mac PRIVATE_EXPECTED_MAC --include-details --include-apps
   ```

   The `--include-details` and `--include-apps` flags are **new in this branch** and must pass current integration checks before live use; they add read-only `includeDetailInfoList=true` and `includeInstalledApks=true` while retaining `includeInstalledFirmware=true`. The code performs **only a signed GET**; credentials are read from `SAS_PAXSTORE_API_KEY` / `SAS_PAXSTORE_API_SECRET` in the authorized local environment. Default no `--freeze` and no device mutation.

   - If `access_state=OBSERVED`, retain the private receipt under `survey/output/hh-cc-reader/`. Extract exact firmware name, install time, part number/Android version (if returned), and application package/version as **separate domains**. Never make firmware equal to a PFT app version by numeric similarity.
   - If a serial is returned but the explicitly expected MAC is absent, the new adapter classifies `IDENTITY_INCOMPLETE` instead of silently confirming Kiosk4; seek a separate same-device binding from existing approved records.
   - If the API returns `FIRMWARE_FIELD_ABSENT`, inspect `terminalDetail` and `installedApks` but retain the missing firmware discriminator; check whether the management record is stale/out of scope.
   - If ESI is not authorized, do **not** try public account registration or a guessed endpoint. Route through Control Center/IngEstate account owner, legitimate BofA/Experian support case, or properly approved customer-managed PAXSTORE read-only role.
5. **Classify metadata by native fields:** use `Classify-HHCCReaderVersionDomain.cmd` on a private labeled capture with `section`, `field_heading`, `value`, optionally `package_name`, `package_id`, `install_time`. Read-only access to a value is **not** evidence of a supported update method. `BASELINE_LOCKED` is eligible only after same-device binding, native domain and source freshness; this task may stop successfully at a domain-bound observation even if deployment-related policy is incomplete.
6. **If still unresolved:** issue a **bounded exact question** based on the missing field (e.g., “Please provide the current installed firmware name and Android version as shown in the enrolled A80 record, with last-check-in timestamp and part number”) rather than requesting a firmware image, rollback mechanism or another generic troubleshooting session.
7. **Emit private receipts and an email-facts candidate** (not a sent email). Preserve the original Google Drive H&H evidence owner, case thread and queue. Sync only sanitized review-approved contracts into public SysAdminSuite. Retain send state `DRAFT_NOT_SENT` until operator sends and actual receipt exists.

## Metadata contract and typed proof

Required outputs per **one exact reader**:

```json
{
  "schema": "hh-a80-network-metadata-observation/v1",
  "reader_identity_ref": "PRIVATE_IDENTITY_REF_ONLY",
  "identity_state": "UNIQUE_TARGET_RESOLVED | IDENTITY_INCOMPLETE | MISMATCH",
  "network": {
    "lan_observation_state": "PREVIOUSLY_PROVED | UPDATED_PROOF | INCONCLUSIVE",
    "inbound_management_state": "NOT_REQUIRED | SERVICE_OBSERVED | NO_SUPPORTED_LISTENER_PROVED",
    "egress_management_state": "DEVICE_UI_SERVICE_CHECK | DESTINATION_OBSERVED | NOT_OBSERVABLE",
    "management_owner_state": "ESTATE_BOUND | CANDIDATE | ACCESS_GATE"
  },
  "source_surface": "EXPERIAN_CONTROL_CENTER | PAXSTORE_OPENAPI | PROVIDER_RECORD | DEVICE_UI",
  "observed_at": "OBSERVATION_TIMESTAMP_OR_NULL",
  "management_last_checkin_at": null,
  "labeled_observations": [
    {
      "section": "Installed Firmware",
      "field_heading": "Firmware name",
      "value": "OBSERVED_VALUE_ONLY",
      "version_domain": "paxstore_installed_firmware_name"
    }
  ],
  "part_number": null,
  "android_os_version": null,
  "application_versions": [],
  "firmware_observation_state": "DOMAIN_BOUND | OBSERVED_NAME_ONLY | FIELD_ABSENT | SOURCE_ACCESS_BLOCKED",
  "firmware_applies_to_bound_reader": false,
  "vendor_email_facts_state": "FACTS_DRAFTED_NOT_SENT",
  "mutation_authorized": false,
  "mutation_performed": false
}
```

The JSON above is a **schema example only**, not a claim that these values were observed on Kiosk4. Real serial/MAC/IP/TID, tenant keys, traffic dumps, captured responses and client data belong only in private ignored local evidence; never commit them to Git or paste them into external correspondence without operator approval. A source with firmware only can still produce `OBSERVED_NAME_ONLY`, which is actionable progress; adding Android/app metadata improves the email but does not revoke the observed firmware.

## Network protocol failure interpretation (non-terminal by design)

| Observed result | Correct interpretation | Next independent path |
| --- | --- | --- |
| ICMP timeout | ICMP blocked or no reply from this path; device-offline **not proven** | current L2 / route authority, then management |
| TCP/443 inbound closed/filtered | No supported **inbound** reader listener identified by that probe | outbound service/terminal-management API; do not scan a list of random ports |
| No ADB USB or TCP | ADB transport unavailable in this provisioned build | provider management and existing Netstat/Connectivity receipts |
| No passive frames on Admin Box | Ordinary switched LAN does not deliver another host's unicast to the workstation | authorized switch mirror / firewall / DNS log, or management API |
| PAXSTORE API permission error | Credential/role/tenant mismatch specific to PAXSTORE | authorized account owner, Control Center/IngEstate, provider export |
| Reader in terminal portal but no firmware field | Device enrolled but installed value absent/stale/not exposed | read role/last-checkin, alternate owner source, exact vendor question |
| OS firmware observed, PFT unanswered | Partial **success** across different software domains | request payment-app/PFT label separately; preserve firmware result |
| Vendor model-family string differs | Package-compatibility mapping not proved | compare same-device SKU/PN/Android field; no flash |

## Email readiness contract

Produce a small private fact table, with explicit confidence: `proven installed firmware`, `proven Android/PN`, `proven payment-app/PFT`, `proven management plane`, `provider still needs to clarify`. If a field is absent, **do not fabricate it**; ask Aaron a narrower question. The email should acknowledge known PAX A80/AxiaMed hardware, differentiate the OS package names from PFT application version, and request compatibility/read-only retrieval details only for fields the agent could not verify.

### Acceptance gates

- Read-only LAN is treated as one optional observation lane, **never** a prerequisite to management API/portal metadata.
- At least one same-device authoritative installed-firmware field **or** exact typed provider access blocker with concrete source and next credential/role owner.
- Firmware, Android and application/PFT domains remain separately labeled even when they appear in one payload.
- An empty inbound port scan or ADB result must not terminate the parent mission.
- No device/network/account mutation; no rollback discussion promoted as active work; no second round of exhausted physical tests.
- Tests: `python Tests/survey/test_hh_cc_reader_paxstore_terminal_observe_contracts.py`; `python Tests/survey/test_hh_cc_reader_firmware_protocol_contracts.py`; `python Tests/survey/test_hh_cc_reader_paxstore_terminal_firmware_contracts.py`. Real Windows/credential/terminal proof remains separate and must not be invented from fixtures.

## Source references and boundaries

- PAXSTORE official OpenAPI `TerminalApi.getTerminalBySn`: https://github.com/PAXSTORE/paxstore-openapi-java-sdk/blob/master/docs/TERMINAL_API.md
- PAXSTORE Administrator Center hardware / Installed Firmware / Installed Apps interface: https://faqs.pax.us/wp-content/uploads/2020/05/PAXSTORE-Reseller-Admin-Guide_v1.0.pdf
- PAX official Control Center and AxiaMed A80 relationship: https://www.pax.us/about/press-room/pax-technology-inc-and-axiamed-partner-to-provide-optimal-healthcare-payment-experience-with-android-based-a920-a80/
- This public runbook describes a **possible supported path**, not an authenticated H&H estate read. Existing H&H private Drive evidence and the local agent's proof receipts decide the live result.
