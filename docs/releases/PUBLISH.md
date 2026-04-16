# Publishing a portable build

## What the build produces

From the repo root on a trusted build machine:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\build\New-PortableArtifact.ps1 -Version 0.1.0
```

Outputs under `dist/` (gitignored locally):

- `SysAdminSuite-Portable-v0.1.0.zip`
- `SysAdminSuite-Portable-v0.1.0.manifest.json` (real `checksumSha256`, UTC `publishedUtc`, optional `gitCommit`)

Copy **both** files to your approved channel (internal share, GitHub Release asset, or packaging pipeline input).

## Verify before wide distribution

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-PortableArtifactSmoke.ps1 `
  -ZipPath .\dist\SysAdminSuite-Portable-v0.1.0.zip `
  -ManifestPath .\dist\SysAdminSuite-Portable-v0.1.0.manifest.json
```

## Approved channel examples

- **SMB:** mirror only the zip + manifest to `\\server\share\SysAdminSuite\releases\` and point operators at the manifest for checksum verification.
- **GitHub Releases:** upload the zip and manifest as release assets; paste checksum into release notes for human verification.
- **Endpoint management:** use the zip as a Win32/LOB app source per your tenant process.

Restricted endpoints should follow the rollback steps in [DEPLOYMENT_ARTIFACTS.md](../DEPLOYMENT_ARTIFACTS.md).
