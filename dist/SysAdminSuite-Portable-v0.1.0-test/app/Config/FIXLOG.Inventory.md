# Inventory Script Fix Log

**Scope:** `Inventory-Software.*.ps1`  
**Current live:** `Inventory-Software.v1.1.2-SafeProps+GuardedSuperset.ps1`

## Changelog
- **v1.1.2 — SafeProps+GuardedSuperset**
  - Replaced raw registry reads (`$p.InstallDate`, etc.) with null-safe access:
    `(($p.PSObject.Properties['Name'])?.Value)` to survive StrictMode + missing values.
  - Rewrote superset block with explicit guard:
    skip when `$perHost` has no `Items`, avoiding `.Items` on `$null`.
- **v1.1.1 — DisplayNameSafe+Preflight**
  - Guaranteed banner + `Preflight-Repo` at start.
- **v1.1.0 — DisplayNameSafe**
  - Null-safe `DisplayName` handling.

## Operational tips
- Always run:
  ```powershell
  Get-ChildItem *.ps1 | Unblock-File
  . .\GoLiveTools.ps1 -RepoHost 'LPW003ASI037'
  Preflight-Repo -RepoRoot $RepoRoot
