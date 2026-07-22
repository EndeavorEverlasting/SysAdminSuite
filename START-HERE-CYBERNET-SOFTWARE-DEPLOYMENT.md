# Start Here — Cybernet Software Deployment

Use this page when an authorized technician or administrator needs to install approved software on Cybernet workstations.

## Complete client configuration

When the assignment includes the client's power-button, Privacy/Menu-button, no-sleep, COM-port, and software preferences together, use the composed workflow instead of running disconnected procedures:

- **Complete technician guide:** [`docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md`](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md)
- **One-target launcher:** `Run-CybernetClientConfiguration.cmd`
- **PowerShell entrypoint:** `Hardware/Cybernet/Invoke-CybernetClientConfiguration.ps1`
- **Preference source of truth:** `Config/cybernet-client-preferences.json`

The composed workflow applies and validates hardware first, installs the approved six-package clinical set with AutoLogon last, validates hardware again, and emits a technician software-acceptance checklist. It never reboots a target or repairs COM ports remotely.

## Software-only workflow

Use the software-only path when the hardware preferences have already been independently applied and validated.

## Choose the right guide

- **Complete hardware-and-software guide:** [`docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md`](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md)
- **Step-by-step software operator tutorial:** [`docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md`](docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md)
- **Technical transport reference:** [`docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`](docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md)
- **Approved-package lifecycle:** [`docs/AUTODIDACT_INSTALL_WORKFLOW.md`](docs/AUTODIDACT_INSTALL_WORKFLOW.md)
- **Teardown doctrine:** [`docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md`](docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md)

## Safe launch order

1. Confirm the package, target, ticket/change, operator, and maintenance window are authorized.
2. Open the repository root in **Git Bash on an approved Windows admin workstation or admin VM**.
3. Review current help:

   ```bash
   bash bash/apps/sas-install-apps.sh --help
   ```

4. Run one target with `--dry-run`.
5. Review the package, task, staging, result-retrieval, and cleanup plan.
6. Run one authorized live pilot by removing only `--dry-run`.
7. Review the local log and result CSV.
8. Confirm the application or shortcut works through the normal technician workflow.
9. Expand to a small explicit batch only after the pilot is accepted.

## BCA pilot command

Dry run:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy \
  --dry-run
```

Live pilot after approval and review:

```bash
bash bash/apps/sas-install-apps.sh \
  --targets CYBERNET-PILOT-01 \
  --package bca \
  --allow-legacy
```

Never paste a password into the command. The Windows-native lane uses the current approved Windows administrative token. Do not use more than 25 explicit targets, and do not treat 25 as a recommended first batch.

## Proof boundary

PR #229 is the authoritative implementation and production-pilot record for this Task Scheduler lane. It records one successful authorized BCA pilot with `HOST_OK`, verified task/staging cleanup, returned result evidence, and technician application acceptance.

The deployment script does not create a VM, authorize another target, reboot a workstation, or uninstall software. A Windows admin VM is only an eligible controller when it already satisfies the documented prerequisites.
