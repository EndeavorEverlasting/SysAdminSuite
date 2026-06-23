# QR Web Interface

## Purpose

The dashboard QR Builder lets technicians generate scannable payloads for approved SysAdminSuite workflows.

The web dashboard does not execute network probes directly. Browser security blocks DNS, ping, SMB, WMI, SNMP, and Nmap from a normal web page.

Instead, the dashboard generates payloads that technicians can scan, paste, review, and run in an approved admin shell.

## Standard target directory

Technicians should place target lists here:

```text
SysAdminSuite/dashboard/targets
```

Browser security requires manual folder selection.

Dashboard workflow:

1. Open `dashboard/index.html`.
2. Go to `QR Builder`.
3. Click `Choose Target Directory`.
4. Select `SysAdminSuite/dashboard/targets`.
5. Pick a `.txt` or `.csv` target file.
6. Choose the desired payload use case.
7. Preview the exact payload.
8. Copy, download, or show the large QR.

## Payload posture

Bash payloads are preferred for Northwell-targeted development.

PowerShell payloads are preserved as legacy interactive payloads for environments where PowerShell is still approved.

PowerShell payloads must not use:

```text
Invoke-Expression
iex
EncodedCommand
Invoke-WebRequest download tricks
policy bypass theater
```

## AD versus network scanning

AD exports show the registered device population.

Nmap and network probes only show what is reachable right now.

For Cybernet reconciliation, use this order:

```text
AD registered objects
then recon tracker
then DNS resolution
then Nmap reachability
then live serial checks only where allowed
```

## QR rendering dependency

The standalone QR builder attempts to load a QR rendering library in this order:

```text
js/vendor/qrcode.min.js
https://cdn.jsdelivr.net/npm/qrcode@1.5.4/build/qrcode.min.js
```

For offline use, vendor the local file at:

```text
dashboard/js/vendor/qrcode.min.js
```

If the QR rendering library is unavailable, the dashboard still previews, copies, and downloads payload text, but it cannot draw a scannable QR canvas.

## Review notes

This feature is implemented as:

```text
dashboard/js/panel-qr-standalone.js
```

It is loaded after:

```text
dashboard/js/bundle.js
```

This keeps the initial patch small and reviewable. A later agent can fold the panel into `panel-qr.js`, `app.js`, and `build-bundle.js` once the standalone behavior is accepted.
