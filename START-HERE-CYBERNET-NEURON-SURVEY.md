# Start Here: Cybernet / Neuron Network Survey

This is the current priority field workflow for SysAdminSuite technicians.

Use it when you need to locate Cybernet or Neuron devices from approved deployment documentation using a local admin workstation, target manifests, and conservative approved network discovery.

## Need subnets first

Run this first from Git Bash/MSYS2 Bash on the connected admin workstation:

```bash
bash survey/sas-find-local-subnets.sh --site <site-code>
```

Example:

```bash
bash survey/sas-find-local-subnets.sh --site nsuh
```

The command produces:

- `survey/output/local_subnet_finder/<site>_<timestamp>/subnet_candidates.txt`
- `survey/output/local_subnet_finder/<site>_<timestamp>/subnet_candidates.csv`
- local context under `context/`
- `SUMMARY.md`

Use `subnet_candidates.txt` as the fast approved CIDR shortlist for the rest of the survey workflow.

## Full fast path

1. Read the full tutorial: [`docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md`](docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md)
2. Put approved local target CSVs in `survey/input/`
3. Run `bash tests/bash/smoke-bash-windows-runtime.sh`
4. Find local candidate subnets with `bash survey/sas-find-local-subnets.sh --site <site-code>`
5. Build manifests with `bash survey/sas-survey-targets.sh`
6. Capture local context with `bash survey/sas-device-snapshot.sh`
7. Run approved `nmap -sn` discovery only against confirmed scope
8. Resolve Nmap evidence with `bash survey/sas-resolve-nmap-evidence.sh`
9. Package output from `survey/output/`, `survey/artifacts/`, and `logs/nmap/`

## Hard rules

- Do not commit live target CSVs, scan output, dashboards, ZIPs, serials, MACs, or site evidence.
- Do not run broad scans without approved scope.
- Do not use spoofing, decoys, stealth flags, vuln scripts, brute force, or credential attacks.
- Do not claim Nmap found a serial unless an approved serial evidence source actually produced it.

This workflow is for asset discovery and reconciliation. Keep it boring, clean, and provable.
