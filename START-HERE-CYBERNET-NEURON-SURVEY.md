# Start Here: Cybernet / Neuron Network Survey

This is the current priority field workflow for SysAdminSuite technicians.

Use it when you need to locate Cybernet or Neuron devices from approved deployment documentation using a local admin workstation, target manifests, and conservative Nmap discovery.

## Fast path

1. Read the full tutorial: [`docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md`](docs/tutorials/CYBERNET_NEURON_NETWORK_SURVEY.md)
2. Put approved local target CSVs in `survey/input/`
3. Run `bash tests/bash/smoke-bash-windows-runtime.sh`
4. Build manifests with `bash survey/sas-survey-targets.sh`
5. Capture local context with `bash survey/sas-device-snapshot.sh`
6. Run approved `nmap -sn` discovery only against confirmed scope
7. Resolve Nmap evidence with `bash survey/sas-resolve-nmap-evidence.sh`
8. Package output from `survey/output/`, `survey/artifacts/`, and `logs/nmap/`

## Hard rules

- Do not commit live target CSVs, scan output, dashboards, ZIPs, serials, MACs, or site evidence.
- Do not run broad scans without approved scope.
- Do not use spoofing, decoys, stealth flags, vuln scripts, brute force, or credential attacks.
- Do not claim Nmap found a serial unless an approved serial evidence source actually produced it.

This workflow is for asset discovery and reconciliation. Keep it boring, clean, and provable.
