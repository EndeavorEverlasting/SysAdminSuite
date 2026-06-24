# PR 46 Cybernet tutorial handoff

Branch: `agent/20260623-pr46-fix-cybernet-tutorial`

## What this branch does

Folds the temporary post-bundle tutorial polish layer into dashboard source (`app.js`, `style.css`, `bundle.js`) and removes `tutorial-polish.js` / `tutorial-polish.css`.

## Related open lanes (do not merge chaotically)

| PR / lane | Role |
|-----------|------|
| **PR #45** | Field tutorial source of truth — technician workflow (`bash/sas-tutorial.sh`, `docs/tutorials/`) |
| **PR #46** | Dashboard-guided Cybernet acquisition tutorial surface |
| **PR #47** | Web QR payload builder (standalone post-bundle module for review safety) |
| **PR #42** | Artifact delivery companion |
| **PR #44** | No-PowerShell dashboard host |

The dashboard should eventually expose one coherent **Cybernet acquisition** flow linking tutorial, QR payloads, target manifests, and artifact delivery without duplicating inconsistent commands.

## Deferred follow-up

- **Cybernet target manifest ingestion** (`Identifier,IdentifierType,DeviceType,HostName,Serial,MACAddress,Source`): extension point exists in `dashboard/js/parsers.js` but is not implemented on this branch. The tutorial final step correctly limits drag-and-drop to dashboard-recognized evidence CSVs only.

## Validation

```bash
node dashboard/build-bundle.js
node --check dashboard/js/app.js
node --check dashboard/js/bundle.js
node dashboard/smoke-test.js
python3 -m py_compile server.py
git diff --check
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1
```

Manual: open `dashboard/index.html`, step through Cybernet tutorial, confirm `--targets-file` on transport steps, resize to 320px for overflow check.
