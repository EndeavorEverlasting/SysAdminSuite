# Survey Low-Noise Skill

Use this skill for survey, preflight, packet-probe, Naabu/Nmap, target-intake, or dashboard probe changes.

## Doctrine

- Treat AD-derived or approved manifests as the population authority.
- Treat Naabu/Nmap output as reachability evidence only.
- Use suite wrappers: `survey/sas-run-naabu-pipeline.sh` or `survey/sas-run-packet-probe.sh`.
- Keep `-silent` on Naabu pipelines.
- Keep `-ec` on reachability profiles unless the profile documents why CDN edges are intentionally in scope.
- Require explicit gates for UDP, all-port, public-target, or subnet host-discovery profiles.
- Write artifacts only to local ignored output paths.
- Classify guest-network failures as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.

## Change process

1. Read `docs/OPERATIONAL_POSTURE.md`, `survey/README.md`, and the relevant survey docs.
2. Make the smallest Bash-first change.
3. Do not edit PowerShell files unless the user explicitly asked for PowerShell work.
4. Validate with scoped, non-live checks unless the user requested an approved field run.
