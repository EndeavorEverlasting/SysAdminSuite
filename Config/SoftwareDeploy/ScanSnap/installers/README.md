# ScanSnap installer drop zone

Place the operator-provided ScanSnap installer (`.exe` or `.msi`) in this folder on **Admin Box 1 (`LPW003ASI173`)**.

Then bind it (does not invent switches — you must supply them from package evidence):

```powershell
.\Bind-ScanSnapPackage.ps1 `
  -InstallerPath .\installers\<your-file.exe> `
  -SilentArgs '<exact silent args from package evidence>' `
  -DetectType file `
  -DetectValue 'C:\Program Files\...\ScanSnap....exe'
```

Binary installers and the bound `package.local.manifest.json` are gitignored machine-local truth. The tracked `package.manifest.json` remains an unbound template so repository refreshes cannot erase or publish a qualified Admin Box package.
