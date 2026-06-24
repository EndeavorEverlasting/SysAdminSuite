# PR 46 Cybernet tutorial handoff

Branch: `codex/prepare-tutorial-for-cybernet-target`

## What this branch does

Folds the Cybernet target acquisition tutorial into dashboard source (`dashboard/js/app.js`, `dashboard/css/style.css`, `dashboard/js/bundle.js`) and adds the dashboard tutorial surface in `dashboard/index.html`.

## Current status after recheck

- PR #46 is open, mergeable, and no longer behind `main`.
- Dashboard smoke samples are present on current `main` and the PR branch.
- GitHub Actions **Dashboard Smoke** completed successfully for the PR head.
- CodeRabbit status is green for the PR head.
- GitHub Actions **Pester** still fails in the `test` job. This matches the previously documented baseline/environment lane and is not caused by the dashboard tutorial files.

## Related lanes (do not merge chaotically)

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
- **Pester baseline triage**: the Pester workflow still has pre-existing fixture/environment failures and should be handled separately from this dashboard tutorial PR.

## Validation

Automated / syntax:

```bash
node dashboard/build-bundle.js
node --check dashboard/js/app.js
node --check dashboard/js/bundle.js
node dashboard/smoke-test.js
python3 -m py_compile server.py
git diff --check
```

GitHub Actions:

- Dashboard Smoke: PASS
- Pester: FAIL, pre-existing baseline/environment lane

Manual QA before merge:

1. Open `dashboard/index.html`.
2. Step through all Cybernet tutorial steps.
3. Confirm posture/identity commands use `--targets-file`.
4. Confirm survey step uses `--file`.
5. Confirm final step only references dashboard-recognized evidence CSVs.
6. Test Copy button and clipboard fallback.
7. Resize to 320px width and confirm no horizontal overflow.
