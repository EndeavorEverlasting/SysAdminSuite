# ScanSnap installer drop zone

Place the ScanSnap Home installer artifacts in this folder on **Admin Box 1 (`LPW003ASI173`)**.

## Current qualified package (Lane A, 2026-10-07)

| Field | Value |
|---|---|
| Product | ScanSnap Home 4.1.0.5 (current Ricoh/PFU "ScanSnap" Windows software) |
| Bound installer | `WinSSHomeInstaller_4_1_0.exe` |
| Response file | `WinSSHomeInstaller_4_1_0.iss` (must sit beside the exe) |
| Authoritative download | `WinSSHOfflineInstaller_4_1_0.exe` from Ricoh CDN |
| Source URL | `https://origin.pfultd.com/downloads/ss/sshinst/w-410/WinSSHOfflineInstaller_4_1_0.exe` |
| Vendor page | `https://www.pfu.ricoh.com/imaging/ssacc/en/start_download_21.html` |

Acquire the offline installer from the vendor page/CDN, extract (run until EULA / temp `SSHomeDownloadInstaller\download`), copy the Home installer + matching `.iss` here, then bind:

```powershell
.\Bind-ScanSnapPackage.ps1 `
  -InstallerPath .\installers\WinSSHomeInstaller_4_1_0.exe `
  -SilentArgs '-s -f1".\WinSSHomeInstaller_4_1_0.iss"' `
  -DetectType file `
  -DetectValue 'C:\Program Files (x86)\PFU\ScanSnap\Home' `
  -Type exe
```

SilentArgs come from the vendor-shipped InstallShield response file (`[InstallShield Silent]`). DetectValue is the Ricoh-documented 64-bit Home folder (also matches `szDir` in the `.iss`).

Binary installers and `.iss` files are gitignored. Only the binding in `package.manifest.json` is tracked.
