# Harvest: feature/2026-05-21-live-serial-probe

- Source ref: `origin/feature/2026-05-21-live-serial-probe`
- Base ref: `origin/main`

## Commit Summary

```text
679bba2 (HEAD -> forensics/replit-full-harvest-v1, origin/main, origin/harvest/2026-05-22-neuron-tooling-from-pr6, origin/HEAD) docs: add branch convergence ledger
95efd9d docs: clarify repo root and pull before live serial probe
fd70e57 feat: add field bootstrap helper for repo root and pull
6812c32 test: add live serial probe contract test
1dce45a test: add live serial probe sample identity data
15a439d test: add live serial probe sample manifest
bac4a5c docs: add live serial probe sprint guide
42b4893 feat: add live serial probe dashboard renderer
4702f3b feat: add live serial probe workflow
b33982b (origin/feature/2026-05-21-live-serial-probe) test: add live serial probe contract test
85deddd test: add live serial probe sample identity data
e7fde60 test: add live serial probe sample manifest
a16ff32 docs: add live serial probe sprint guide
ab4e7ce feat: render glowing live serial probe dashboard
2f72cda feat: add live serial and MAC probe workflow
e68160b (origin/feature/2026-05-21-live-serial-probe-main-sync, subrepl-gvaukxlz) Improve git hooks and scripts for safer pushes
72ad1a9 feat: auto-sync Replit commits to GitHub via post-commit hook + post-merge script
b341861 feat: auto-sync Replit commits to GitHub via post-merge script
c314f48 Task #16: Sync GitHub main with Replit (push 20 commits to origin)
8b8dc9a Task #15: Keep server running after browser opens — system-tray icon + crash monitor
a530f01 Add dashboard launcher to Launch-SysAdminSuite-Runtime.bat (Task #14)
05fdd7c Add tutorial completion badge tracking which dashboard panels have been explored
dbbeb48 Task #12: Add keyboard shortcut (?) to open dashboard tour from anywhere
b573ecc Task #11: Let the Bash tutorial run each workflow step for real and show live output
3a81947 Retire sources.csv and update fetch-map docs for YAML-only workflow (Task #10)
c0f1787 Add dashboard/samples/sources.yaml with demo data for Software Tracker panel
4d8659e Add live install-status tracking to the Software Tracker dashboard panel
4a7881f Add Harold splash screen launcher for the web app dashboard (Task #7)
638ccb8 feat: Add folder-watch / File System Access API integration for auto-refresh (Task #6)
5fd396d Add live SNMP and TCP port probing via authenticated local WebSocket relay
8eda880 Add self-contained demo mode: "Load Sample Data" button populates all panels
2ddae1d feat: Tutorials for All Avenues (PowerShell, Bash, Web App)
02dff95 Task #2 (Round 8 approved-with-comments): Address reviewer suggestions
2e5bc1d Git commit prior to merge
2fcdc08 (gitsafe-backup/main) Improve server startup to prevent port binding errors
7fba202 Post-merge setup completed successfully
71dc77a fix: empty-targets guard, README 13 cases, URL consistency, multiline CSV test
43568ea Git commit prior to merge
e1f320d feat: add Bash-on-Windows field survey scripts
0cec520 docs: enforce Bash-on-Windows runtime contract
```

## Diff Stat

```text
 AGENTS.md                                          |  93 ++++-
 deployment-audit/docs/LIVE_SERIAL_PROBE_SPRINT.md  | 114 ++++++
 .../sas-render-live-serial-dashboard.py            | 338 ++++++++++++++++++
 .../tests/test_live_serial_probe_contracts.sh      |  31 ++
 docs/AI_RUNTIME_CONTRACT.md                        | 122 +++++++
 docs/COMMAND_CATALOG.md                            | 151 ++++++++
 survey/README.md                                   |  83 ++++-
 survey/fixtures/live_serial_identity.sample.csv    |   6 +
 survey/fixtures/live_serial_manifest.sample.csv    |   6 +
 survey/sas-device-snapshot.sh                      | 125 +++++++
 survey/sas-live-serial-probe.sh                    | 384 +++++++++++++++++++++
 survey/sas-neuron-environment.sh                   | 143 ++++++++
 tests/bash/smoke-bash-windows-runtime.sh           |  44 +++
 13 files changed, 1636 insertions(+), 4 deletions(-)
```

## Name Status

```text
M	AGENTS.md
A	deployment-audit/docs/LIVE_SERIAL_PROBE_SPRINT.md
A	deployment-audit/sas-render-live-serial-dashboard.py
A	deployment-audit/tests/test_live_serial_probe_contracts.sh
A	docs/AI_RUNTIME_CONTRACT.md
A	docs/COMMAND_CATALOG.md
M	survey/README.md
A	survey/fixtures/live_serial_identity.sample.csv
A	survey/fixtures/live_serial_manifest.sample.csv
A	survey/sas-device-snapshot.sh
A	survey/sas-live-serial-probe.sh
A	survey/sas-neuron-environment.sh
A	tests/bash/smoke-bash-windows-runtime.sh
```
