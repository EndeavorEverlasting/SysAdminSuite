# DEPLOYMENT ARTIFACTS

## Goal
Ship SysAdminSuite to restricted runtime endpoints as versioned artifacts, not as repository sync operations.

## Artifact Contract
- Portable artifact name format: `SysAdminSuite-Portable-vX.Y.Z.zip`
- Version source: explicit script parameter (`-Version`).
- Artifact root layout:
  - `app/` - runtime scripts and launchers
  - `data/` - endpoint-local mutable data
  - `logs/` - runtime logs
  - `manifest/` - update manifest snapshot bundled with release
- Rollback rule: keep previous artifact zip and previous extracted runtime folder until smoke validation passes.

## Build Path (Trusted Build Machine)
1. Build from repository checkout.
2. Execute:
   - `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\build\New-PortableArtifact.ps1 -Version 0.1.0`
3. The build writes **`dist/SysAdminSuite-Portable-v{Version}.zip`** and a matching **`dist/SysAdminSuite-Portable-v{Version}.manifest.json`** with a real SHA256 and UTC timestamp (and `gitCommit` when built inside a git repo).
4. Publish **both** the zip and the manifest to your approved distribution location. See [releases/PUBLISH.md](releases/PUBLISH.md).
5. Optional offline verification:
   - `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-PortableArtifactSmoke.ps1 -ZipPath .\dist\SysAdminSuite-Portable-v0.1.0.zip -ManifestPath .\dist\SysAdminSuite-Portable-v0.1.0.manifest.json` (adjust version paths; see [releases/PUBLISH.md](releases/PUBLISH.md)).

## Runtime Layout (Restricted Endpoint)
- `%LocalAppData%\SysAdminSuite\app`
- `%LocalAppData%\SysAdminSuite\data`
- `%LocalAppData%\SysAdminSuite\logs`

Mirror only `app` during updates if preserving local `data` is required.

## Update Manifest Spec
Use a JSON manifest (`Config/update-manifest.sample.json`) with:
- `version` - semantic or date-based version label
- `package` - file name of portable artifact
- `checksumSha256` - package checksum
- `publishedUtc` - UTC timestamp
- `notes` - optional short update summary

## Manual Operator Update Procedure
1. Download/copy artifact from approved source.
2. Verify SHA256 checksum against manifest.
3. Stop SysAdminSuite process if running.
4. Backup existing `app` folder as `app.previous`.
5. Extract new artifact and replace `app` folder only.
6. Launch runtime via `Launch-SysAdminSuite-Runtime.bat`.
7. Validate startup and primary QR task dispatch.
8. If validation fails, restore `app.previous`.

## Approved Transport Methods
- Internal SMB file share
- Browser download from approved release location
- Enterprise software deployment tooling (Software Center/Intune/SCCM)

## Verification Requirement
Every promoted artifact must publish a SHA256 checksum and include a manifest entry before endpoint deployment.
