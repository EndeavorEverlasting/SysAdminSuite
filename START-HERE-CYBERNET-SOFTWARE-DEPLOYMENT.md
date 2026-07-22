# Start Here — Cybernet Client Configuration and Software Deployment

Use this page when an authorized technician or administrator needs to configure Cybernet hardware preferences, install approved software, or both.

## Choose the correct workflow

| Assignment | Start here | Primary launcher |
|---|---|---|
| Hardware preferences **and** approved software together | [Complete Cybernet client configuration tutorial](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md) | `Run-CybernetClientConfiguration.cmd` |
| A combined run failed or needs rollback/recovery | [Cybernet client configuration troubleshooting](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md) | Inspect the failed run before retrying |
| Hardware preferences only | [`Hardware/Cybernet/README.md`](Hardware/Cybernet/README.md) | `Run-CybernetBatchConfiguration.cmd` |
| Software only, with hardware already validated | [Cybernet software deployment tutorial](docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md) | `bash/apps/sas-install-apps.sh` |
| Generic browser-guided software pilot | Dashboard → **Start Software Deployment** | `START-HERE-SysAdminSuite-Dashboard.bat` |

The browser tutorial is software-only. It does not apply Cybernet no-sleep, physical power-button, display-button, or COM policy.

## Complete client configuration

Use the composed workflow when the assignment includes the client's power-button, Privacy/Menu-button, no-sleep, COM-port, and software preferences together.

Current authorities:

- **Operator tutorial:** [`docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md`](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md)
- **Troubleshooting and rollback:** [`docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md`](docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md)
- **One-target launcher:** `Run-CybernetClientConfiguration.cmd`
- **PowerShell entrypoint:** `Hardware/Cybernet/Invoke-CybernetClientConfiguration.ps1`
- **Preference source of truth:** `Config/cybernet-client-preferences.json`
- **Approved package-set catalog:** `configs/software-packages/windows-native-package-sets.json`

The composed order is:

1. hardware Apply and readback;
2. stop before software when hardware or COM readiness fails;
3. approved six-package installation with AutoLogon last;
4. result retrieval and cleanup verification;
5. post-software hardware validation;
6. technician application/shortcut acceptance;
7. separately authorized reboot and AutoLogon observation when required.

The workflow never reboots a target or repairs COM ports remotely.

## One-target operator quick start

Enter the repository first:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'
```

Read launcher help:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Help
```

Plan one authorized pilot without target or software-share contact:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Plan <AUTHORIZED-CYBERNET>
```

Required Plan status: `PLAN_READY`.

After reviewing the newest run under `survey\output\cybernet_hardware\client-configuration-*`, apply the same authorized target:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Apply <AUTHORIZED-CYBERNET>
```

Required automated status: `APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED`.

Complete `technician_software_acceptance.txt`, then run read-only validation:

```powershell
Set-Location -LiteralPath '<SYSADMINSUITE-REPO-ROOT>'

.\Run-CybernetClientConfiguration.cmd Validate <AUTHORIZED-CYBERNET>
```

Required validation status: `HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED`.

Those statuses do not prove application behavior, reboot success, or AutoLogon. Record those separately through the approved technician/ticket process.

## Software-only workflow

Use the software-only path only when the Cybernet hardware preferences have already been independently applied and validated.

### Guides

- **Step-by-step software operator tutorial:** [`docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md`](docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md)
- **Technical transport reference:** [`docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md`](docs/SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md)
- **Approved-package lifecycle:** [`docs/AUTODIDACT_INSTALL_WORKFLOW.md`](docs/AUTODIDACT_INSTALL_WORKFLOW.md)
- **Teardown doctrine:** [`docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md`](docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md)

### Safe software-only launch order

1. Confirm the package, target, ticket/change, operator, and maintenance window are authorized.
2. Open the repository root in Git Bash on an approved Windows admin workstation or admin VM.
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

### BCA software-only pilot

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

## Evidence and proof boundary

Combined workflow evidence is written beneath:

```text
survey\output\cybernet_hardware\client-configuration-*
```

The primary files are:

- `cybernet_client_configuration_summary.json`
- `operator_handoff.txt`
- `technician_software_acceptance.txt`
- stage console logs and parameter documents

Software controller evidence is also written under `bash/apps/output/`.

Repository documentation, fixtures, and CI prove command shape and composition only. They do not authorize another target, prove a real display supports VCP `0xCA`, prove a real installation, reboot a workstation, prove automatic sign-in, or replace technician acceptance.
