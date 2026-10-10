# Start here: SystemRescue disk recovery

Use [`recovery/systemrescue/README.md`](recovery/systemrescue/README.md) and the guarded entry point:

```bash
bash recovery/systemrescue/sas-recovery.sh --help
```

This lane covers device identity, source read-only enforcement, new or resumed GNU ddrescue imaging, evidence checkpoints, read-only image/BitLocker/NTFS attachment, user-data auditing and evacuation, cleanup, and QR-safe pointer commands.

For controller/media/PCIe-path diagnosis after preservation, use [`recovery/systemrescue/NVME_FORENSICS.md`](recovery/systemrescue/NVME_FORENSICS.md). The forensic commands keep the explicit source unmounted and host-read-only, write verbose evidence to files, print viewport-bounded summaries, and can automatically capture the postmortem from a sustained read-only NVMe reproduction test.

To carry only the reusable tooling onto a writable SystemRescue companion/data filesystem, use:

```bash
bash recovery/systemrescue/export-field-kit.sh --target-root /mnt/field-media
```

Verify the exported manifest before use. Do not assume the SystemRescue ISO/hybrid boot partition itself is writable.

This lane does not repair the source filesystem or Windows installation.
