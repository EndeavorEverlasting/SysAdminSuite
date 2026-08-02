# Start here: SystemRescue disk recovery

Use [`recovery/systemrescue/README.md`](recovery/systemrescue/README.md) and the guarded entry point:

```bash
bash recovery/systemrescue/sas-recovery.sh --help
```

This lane covers device identity, source read-only enforcement, new or resumed GNU ddrescue imaging, evidence checkpoints, read-only image/BitLocker/NTFS attachment, user-data auditing and evacuation, cleanup, and QR-safe pointer commands.

It does not repair the source filesystem or Windows installation.
