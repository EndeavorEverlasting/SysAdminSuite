# Survey Low-Noise Skill

Use this skill for survey, preflight, packet-probe, Naabu/Nmap, target-intake, or dashboard probe changes.

## Capability dependencies

- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)

## Doctrine

- Treat AD-derived or approved manifests as the population authority.
- Treat Naabu/Nmap output as reachability evidence only unless joined with approved, fresh, complete identity evidence.
- Reuse fresh local evidence before proposing another live probe.
- Use suite wrappers: `survey/sas-run-naabu-pipeline.sh` or `survey/sas-run-packet-probe.sh`.
- Use the canonical profile and operational-posture files rather than copying port/rate/retry defaults.
- Require explicit gates for UDP, all-port, public-target, or subnet host-discovery profiles.
- Write artifacts only to local ignored output paths.
- Classify guest-network failures as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.

## Change process

1. Read `docs/OPERATIONAL_POSTURE.md`, `survey/README.md`, and the relevant survey/profile docs.
2. Use the language-runtime skill to choose the actual implementation surface; suitable new survey work is Bash-first on Windows.
3. Make the smallest change without broadening targets, ports, rates, retries, or mutation posture.
4. Validate with scoped, non-live checks unless the user requested an approved field run.
5. Report the exact proof ceiling of fixture, dry-run, packet, or field evidence.
