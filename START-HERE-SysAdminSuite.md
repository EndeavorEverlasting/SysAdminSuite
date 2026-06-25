# Start Here — SysAdminSuite

You do **not** need to memorize command-line tools to use SysAdminSuite.

## I just downloaded or cloned the repo. What do I click?

Double-click **one** of these files at the repo root:

| File | Best for |
|------|----------|
| **`START-HERE-SysAdminSuite-Dashboard.cmd`** | Primary field entry (recommended) |
| **`SysAdminSuite Dashboard.cmd`** | Desktop shortcut with a friendly name |
| `START-HERE-SysAdminSuite-Dashboard.bat` | Same behavior as the `.cmd` launcher |

All three open the same dashboard and tutorial. Use the `.cmd` file unless your site standard prefers `.bat`.

**Shortcut tip:** Right-click `SysAdminSuite Dashboard.cmd` → **Send to** → **Desktop (create shortcut)**.

## What opens?

1. A small dashboard host starts on your computer (look for a tray icon near the clock).
2. Your browser opens the local dashboard at:

   `http://127.0.0.1:5000/dashboard/?tutorial=cybernet`

3. The browser tab shows the Harold icon. Click **Start Cybernet Survey** to follow the guided tutorial.

No internet is required after the repo is on your machine.

## What about an EXE?

The repo does **not** ship a committed `.exe` today. Field users should use the `.cmd` launcher above.

A future sprint will document shipping or building `SysAdminSuite Dashboard.exe` for shortcut-friendly desktops. See [`docs/DASHBOARD_EXE_FUTURE_SPRINT.md`](docs/DASHBOARD_EXE_FUTURE_SPRINT.md).

Developers can build a local `.exe` now:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\publish-dashboard-entrypoint.ps1
```

Output: `dist/SysAdminSuiteDashboard/SysAdminSuite Dashboard.exe` (gitignored).

## What if it does not open?

1. Run the `.cmd` file from the **repo root**, not from inside a subfolder.
2. Paste into your browser: `http://127.0.0.1:5000/dashboard/?tutorial=cybernet`
3. If the host is missing, run the publish script above once, then double-click the `.cmd` again.
4. Read [`docs/DASHBOARD_ENTRYPOINT.md`](docs/DASHBOARD_ENTRYPOINT.md) for IT troubleshooting.

## When do I use CLI commands?

Only when the dashboard tells you to copy a command, or a runbook explicitly asks for Bash survey steps.

- Cybernet CLI runbook: [`START-HERE-CYBERNET-NEURON-SURVEY.md`](START-HERE-CYBERNET-NEURON-SURVEY.md)

## What files should I never commit?

Live target CSVs, scan output, packaged ZIPs, serials, MACs, and site evidence. Keep them on your admin workstation only.

## More help

- Agent/IT canonical reference: [`docs/DASHBOARD_ENTRYPOINT.md`](docs/DASHBOARD_ENTRYPOINT.md)
- Dashboard UI: [`dashboard/README.md`](dashboard/README.md)
