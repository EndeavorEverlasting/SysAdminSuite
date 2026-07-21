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
- Use `survey/naabu_profiles.json` as the canonical doctrine source and suite wrappers such as `survey/sas-run-naabu-pipeline.sh` or `survey/sas-run-packet-probe.sh` for execution.
- Use "low-noise survey discipline" language; the objective is authorized scope control and local evidence, not reduced monitoring visibility.
- Use the canonical profile and operational-posture files rather than copying port/rate/retry defaults.
- Require explicit gates for UDP, all-port, public-target, or subnet host-discovery profiles.
- Write artifacts only to local ignored output paths.
- Classify guest-network failures as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.
- Treat `feature/naabu-docs-consolidation` as superseded by current `main`; do not revive or merge it without explicit user authorization.
- Port-fallback classification requests route through this skill and its existing capability dependencies. Do not create a second low-noise instruction system.
- Output at this stage is a bounded plan or contract-shaped decision requirement. Network activity, target mutation, approval, and proof escalation require separate authorization.
- The `network_preflight` profile in `Config/low-noise-policy.json` (ports `135,445,3389,9100`) is a separate field preflight profile. Do not confuse it with the canonical Cybernet key-port profile (`80,443,135,445,3389,5985,5986`) from `survey/naabu_profiles.json`.

## Change process

1. Read `docs/OPERATIONAL_POSTURE.md`, `docs/LOW_NOISE_SURVEY_DOCTRINE.md`, `survey/README.md`, and the relevant survey/profile docs.
2. Use the language-runtime skill to choose the actual implementation surface; suitable new survey work is Bash-first on Windows.
3. Make the smallest change without broadening targets, ports, rates, retries, or mutation posture.
4. Validate with scoped, non-live checks unless the user requested an approved field run.
5. Report the exact proof ceiling of fixture, dry-run, packet, or field evidence.
