# SystemRescue NVMe forensics

This lane extends the guarded SystemRescue recovery harness with **read-only NVMe diagnosis**. It exists for cases where a failing Windows disk can still enumerate, but the operator needs to distinguish filesystem/OS symptoms from controller, media, PCIe-path, or power-path failures.

Runtime machine identifiers, serials, terminal photos, recovery keys, private cloud links, and case-specific evidence stay outside Git. Use generic repository examples and store case evidence in the operator's private evidence system.

## What the automation owns

The runner exposes `nvme-baseline`, `nvme-classify-log`, `nvme-read-repro`, and `forensics-qr-catalog`. Show the canonical syntax with:

```bash
bash recovery/systemrescue/sas-recovery.sh --help
```

### `nvme-baseline`

The command:

- re-identifies the explicit NVMe source by model and serial when supplied;
- refuses a mounted source;
- sets and verifies the Linux host block-layer source flag `RO=1`;
- records `lsblk`, `nvme list`, SMART, endpoint/root-path PCIe state, AER counters, and full current `dmesg` to evidence files;
- prints only a viewport-bounded summary.

Example:

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh nvme-baseline \
  --source /dev/nvme0n1 \
  --expect-model 'CONFIRMED MODEL' \
  --expect-serial 'CONFIRMED SERIAL' \
  --workdir /tmp/sas-nvme-case/baseline
```

### `nvme-classify-log`

Use this to analyze a **preserved kernel log without touching the source device**. It is useful when the failure already happened and the operator has a saved `dmesg` artifact.

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh nvme-classify-log \
  --kernel-log /path/to/preserved-dmesg.txt \
  --ddrescue-rc 1
```

The classifier counts NVMe timeouts, controller-reset requests, reset-not-ready events, device-disable-after-reset events, and NVMe buffer-I/O errors. When block errors expose logical-block numbers, it reports only the first and last block identifiers rather than printing long raw log lines.

### `nvme-read-repro`

Use this only **after preservation is complete** and when sustained source reads are justified for diagnosis.

The command:

1. re-identifies the explicit source;
2. refuses if the source or any child is mounted;
3. forces and verifies host `RO=1`;
4. captures a before-baseline;
5. performs a sequential GNU ddrescue read of the physical source to `/dev/null`;
6. captures ddrescue exit status and the kernel-message delta;
7. probes for source presence after failure with a bounded timeout before attempting an after-baseline;
8. emits a bounded postmortem classification.

It never retries automatically, never writes to the source, never mounts it, and never repairs a filesystem.

Possible classifications include:

- `SEQUENTIAL_READ_COMPLETED`
- `BLOCK_IO_FAILURE_WITHOUT_RESET`
- `NVME_TIMEOUT_OR_RESET`
- `NVME_RESET_NOT_READY`
- `NVME_RESET_FAILURE_REPRODUCED`
- `DDRESCUE_EXIT_UNCLASSIFIED`

Example:

```bash
bash /mnt/sas/recovery/systemrescue/sas-recovery.sh nvme-read-repro \
  --source /dev/nvme0n1 \
  --expect-model 'CONFIRMED MODEL' \
  --expect-serial 'CONFIRMED SERIAL' \
  --workdir /tmp/sas-nvme-case/repro
```

The command itself may run for a long time. The operator can leave it in the foreground; postmortem capture occurs automatically when ddrescue completes or fails.

## Evidence model

Verbose output is written to files. Terminal output is intentionally bounded to the configured forensic viewport budget.

Baseline evidence includes:

- `source.txt`
- `nvme-list.txt`
- `smart.txt`
- `pci-endpoint.txt`
- `pci-parent.txt`
- `aer-endpoint.txt`
- `dmesg.txt`
- `summary.txt`

Reproduction evidence additionally includes:

- `before/`
- `read-repro.map`
- `ddrescue.log`
- `ddrescue.exit`
- `dmesg-pre-lines.txt`
- `dmesg-after.txt`
- `kernel-delta.txt`
- optional `after/`
- `repro-summary.txt`

If the source disappears or a reset fails, do **not** blindly relaunch the read in the same boot. Preserve the postmortem and decide the next isolation step.

## Viewport and QRFY contract

A field command has two independent budgets:

1. **transport budget** — the pointer command must fit the QR/QRFY transport;
2. **observable viewport budget** — the evidence needed for the next decision must fit on the terminal screen or be written to a file.

The forensic summary gate assumes a 100-column field terminal and limits the output to at most 20 **visible rows after wrapping**, not merely 20 newline-delimited records. A long line therefore consumes multiple viewport rows. This prevents the prior failure mode where technically short output still scrolled required evidence off-screen.

The forensic commands print bounded summaries rather than raw `dmesg`, SMART, AER, or ddrescue logs. Default to one diagnostic question per screen/photo; verbose evidence stays in files.

Generate pointer commands with:

```bash
bash recovery/systemrescue/sas-recovery.sh forensics-qr-catalog \
  --repo-mount /mnt/sas \
  --source /dev/nvme0n1 \
  --expect-model 'CONFIRMED MODEL' \
  --expect-serial 'CONFIRMED SERIAL' \
  --workdir /tmp/sas-nvme-case \
  --max-chars 240
```

The catalog emits simple pointer commands, not inline loops or script payloads.

## SSD versus slot/platform isolation

A reproduced NVMe reset failure under Linux substantially weakens Windows-only and filesystem-only explanations, but software alone may still not distinguish:

- SSD controller/firmware/media failure;
- M.2 contact/socket intermittency;
- PCIe signal path instability;
- M.2 power delivery instability;
- motherboard/CPU-root-port behavior.

When software evidence remains ambiguous, the decisive next step is powered-off A/B isolation:

- same SSD in another compatible M.2 slot;
- known-good SSD in the suspect slot.

Re-run `nvme-baseline` before and after the physical move so negotiated link state and SMART/kernel evidence are comparable.

## Portable field kit

The repository can export only the reusable SystemRescue tooling to a writable companion/data filesystem:

```bash
bash recovery/systemrescue/export-field-kit.sh --target-root /mnt/field-media
```

The exporter:

- refuses a read-only target;
- refuses to overwrite an existing kit directory;
- copies only repository tooling/docs, not runtime evidence;
- creates `MANIFEST.sha256`.

Verify the copy:

```bash
bash /mnt/field-media/sas-systemrescue-field-kit/recovery/systemrescue/verify-field-kit.sh
```

Do not assume the SystemRescue ISO/hybrid boot partition itself is writable. A writable data partition or companion USB is often the safer persistence target. Identify and verify the target before copying anything.

## Forbidden automation

This lane must not add automatic:

- filesystem repair;
- partition mutation;
- formatting;
- source writes;
- controller firmware update;
- repeated reset/retry loops after device disablement;
- reboot/power-cycle loops;
- copying of private case evidence into the public repository.
