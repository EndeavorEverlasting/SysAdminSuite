# Agilant HQ — Local TCP/IP Printer Mapping

**Status:** SysAdminSuite app workflow implemented in the feature branch; **not field-certified until refreshed build and operator-observed print**.

## One-click operator entry

1. On the **approved Agilant HQ main network** (not Guest or a Northwell network), open the installed SysAdminSuite files and double-click **Map-AgilantHqPrinter.cmd**. Approve the normal administrator/UAC prompt for local TCP port and queue registration.
2. Select a saved profile or enter a descriptive queue name, printer hostname, and an **exactly installed** driver. Read the **current** IPv4 address directly from the copier's Information / Wireless or Ethernet panel. Do not use a saved/historical address as current proof.
3. Click **Preview & preflight**. This checks hostname resolution, TCP/9100, driver presence, existing queue ownership, and proposed port change **without mutating** the printer.
4. Confirm the physical panel IP and Agilant HQ network/site in the checkboxes. If a compatible queue already exists from a manual install, select **Adopt existing queue** and preview again.
5. Click **Map / Repair** and explicitly approve the plan. If DNS is absent or disagrees with the current panel, choose **Use panel IP** and re-preview; this is an explicit recovery, not silent IP selection.
6. Click **Send test page**, then **physically observe the output** and choose **Yes** only if the intended printer actually produced the page. The GUI saves a separate operator-attestation receipt; submission of a test page is never automatically classified as physically printed.

The name/IP/driver fields and last observed IP are saved only by the explicit Save / Update Profile action under the operator's private local Windows application data. Opening a profile **clears panel confirmation and the live panel-IP input**. A saved IP is historical evidence, not permission to map to it.

## Why an IP can appear to change

The manual HQ print succeeded on October 8, 2026 using a printer-panel-confirmed current address. An earlier recorded address did not answer TCP/9100. This establishes an address *difference*, not a proven DHCP reallocation. Possible causes include a DHCP lease change, Wi-Fi/network change, stale DNS, recording error, or another network attachment.

The workflow must keep four concepts separate:

| Evidence | Meaning |
|---|---|
| Printer hostname | Preferred stable logical locator if site DNS reliably resolves it |
| Current printer-panel IPv4 | Fresh out-of-band operator observation for target binding |
| DNS-resolved IPv4 | Network routing candidate, **not** physical identity on its own |
| Existing printer port | Historical Windows configuration, possibly stale |

**Resolution algorithm:**

1. Read-only DNS lookup when hostname supplied; reject multiple A records.
2. Compare resolved IPv4 against the operator-entered current panel IPv4. If unequal, block **DNS_PANEL_MISMATCH**.
3. To recover, operator selects explicit **Use panel IP** and confirms the current address on the physical copier. Without the override, DNS failure blocks.
4. Check TCP/9100 against the selected current address before proposing any mutation. Reachability alone does not establish identity.
5. Prefer a hostname-backed Standard TCP/IP RAW/9100 port *only when DNS agrees with the physical panel*. Otherwise create a dedicated IP-backed port for the freshly confirmed address.
6. If a managed queue already has the correct name, driver and port, report **ALREADY_MAPPED**. If it has a stale managed port, create the new port then switch the queue, leaving the old port available for rollback and any other consumers.
7. If there is a manual pre-existing queue, allow **explicit adoption only** when its current TCP/9100 port resolves to the selected address and the driver matches. Never hijack a different printer with the same display name.
8. Check after mutation that the queue is bound to exactly the selected driver and port. On an error restore the previous queue port and remove an unreferenced newly created port; report **ROLLBACK_INCOMPLETE** if cleanup fails.
9. Persist one local receipt per attempt. Do not mix queue registration, test-page submission and physically observed output into a single success state.

## Important boundaries

- **Not Northwell:** Northwell shared workstation mapping retains the separate SYSTEM / shared UNC / PrintUIEntry /ga contract. Direct TCP/IP ports are forbidden in that use case.
- **Not H&H:** Health & Hospitals printer mapping remains a discovery-only use case until separately authorized.
- **Site:** This product entry is currently authorized for **Agilant HQ** only. A successful printer on one subnet is not approval to map any other organization's device.
- **No scanning:** Only the operator-specified hostname/current IP is probed; no network-wide printer discovery or guessed IP sweep.
- **No driver fetching or security relaxation:** The chosen driver must already be installed. No print-policy weakening or unsolicited firmware work.
- **No forced defaults:** The workflow never sets a printer as the Windows default.
- **No automatic DHCP administration:** A DHCP reservation, if needed, requires the network administrator's approval and the Wi-Fi interface MAC, not the disconnected Ethernet MAC.
- **No remote mutation:** The initial slice changes only the computer on which the app is running.
- **No implicit profile reuse:** Historical IP addresses can be displayed for troubleshooting but must not become live targets without current physical confirmation.
- **No authority from code success alone:** The observed Windows test page printed via manual PowerShell on 2026-10-08; the new application is not live-certified by that earlier event.

## Diagnostics and receipts

Private local files: %LOCALAPPDATA%\SysAdminSuite\PrinterMapping\runs\local-tcp-*.json, physical-observation-*.json and %LOCALAPPDATA%\SysAdminSuite\PrinterMapping\profiles\*.json.

Possible outcomes include READY_TO_MAP, READY_TO_ADOPT, ALREADY_MAPPED, MAPPED_NOW, TEST_PAGE_SUBMITTED, DNS_UNRESOLVED, DNS_PANEL_MISMATCH, TCP_9100_UNREACHABLE, DRIVER_NOT_INSTALLED, UNMANAGED_QUEUE_CONFLICT, ADOPTION_CONFIRMATION_REQUIRED, ROLLBACK_INCOMPLETE and RECEIPT_WRITE_FAILED.

## Validation / release gate

- Python static contract and CI workflow (synthetic, no live target).
- Windows PowerShell 5.1 parser validation via hosted Windows runner.
- Repeat Plan: no queue/port creation.
- First Apply to isolated test printer: matching queue, driver, and port.
- Repeat Apply: idempotent with **ALREADY_MAPPED**.
- Manually simulate stale managed port and DNS/panel mismatch: reject silently using old IP; explicit recovery succeeds with current physical confirmation.
- Existing manual TCP queue with matching address: explicit adoption, no loss of other queues.
- Unrelated existing queue name: fail closed without mutation.
- Rollback simulated failure: previous queue/port preserved or typed incomplete.
- Normal Windows user and UAC prompt behavior; packaged build contains the CMD, GUI and worker.
- Live acceptance: physical **printer-specific** test page actually observed after using this application.

Do not claim deployment or field certification based on repository validation alone.
