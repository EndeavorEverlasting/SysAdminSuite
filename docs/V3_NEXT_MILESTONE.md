# v3 next milestone (chosen slice)

## Decision

The next concrete v3 milestone after foundation + artifact pipeline is **structured logging and version visibility** (logging spine + manifest-driven “what build am I running?”), not a native shell or MSI yet.

## Rationale

- It supports restricted endpoints and audit expectations without rewriting the GUI or adding a second runtime.
- It composes with existing portable artifacts (`*.manifest.json` from `New-PortableArtifact.ps1`).
- It avoids a large binary packaging effort before the team has a single release artifact in production use.

## Scope (suggested)

1. **Single log contract** for long-running scripts: timestamp, severity, operation, machine, optional correlation id; default path under `%LocalAppData%\SysAdminSuite\logs` or repo `logs/` when running from source.
2. **Surface version + git commit** in the GUI status bar or About box, from a small `version.json` or manifest copied next to the app at build time.
3. **Optional:** central helper module `Utilities/Write-SuiteLog.ps1` (or similar) used by new code first; migrate high-traffic scripts incrementally.

## Deferred (explicitly not this milestone)

- C# shell / native host EXE
- MSI/Inno installer
- Engine-aware QR beyond PowerShell (ABI stays PS-first until a host exists)

## Review

Revisit after one shipped portable build has been deployed and smoke-tested on a representative endpoint.
