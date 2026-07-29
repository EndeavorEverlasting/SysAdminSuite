# Survey Low-Noise Skill

Use this skill for survey, preflight, packet-probe, Naabu/Nmap, target-intake, dashboard probe changes, and explicit software-deployment readiness diagnosis. First identify whether the request is a general survey question or the narrower Cybernet deployment transport question.

## Capability dependencies

- [Language Runtime Selection](../../capabilities/language-runtime-selection.md)
- [Mutation and Evidence Boundaries](../../capabilities/mutation-and-evidence-boundaries.md)
- [Proof and Checkpointing](../../capabilities/proof-and-checkpointing.md)

## Doctrine

- Treat AD-derived or approved manifests as the population authority for general survey work.
- Treat Naabu/Nmap output as reachability evidence only unless joined with approved, fresh, complete identity evidence.
- Reuse fresh local evidence before proposing another live probe.
- Use `survey/naabu_profiles.json` as the canonical doctrine source and suite wrappers such as `survey/sas-run-naabu-pipeline.sh` or `survey/sas-run-packet-probe.sh` for general survey execution.
- Use "low-noise survey discipline" language; the objective is authorized scope control and local evidence, not reduced monitoring visibility.
- Use the canonical profile and operational-posture files rather than copying port/rate/retry defaults.
- Require explicit gates for UDP, all-port, public-target, or subnet host-discovery profiles.
- Write artifacts only to local ignored output paths.
- Classify guest-network failures as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.
- Treat `feature/naabu-docs-consolidation` as superseded by current `main`; do not revive or merge it without explicit user authorization.
- Port-fallback classification requests route through this skill and its existing capability dependencies. Do not create a second low-noise instruction system.
- The `network_preflight` profile in `Config/low-noise-policy.json` (ports `135,445,3389,9100`) is a separate field preflight profile. Do not confuse it with the canonical Cybernet key-port profile (`80,443,135,445,3389,5985,5986`) from `survey/naabu_profiles.json`.

## Cybernet software deployment readiness

When the request is how to deploy Cybernet software, whether the deployment path is ready, or how to perform a low-noise iterative deployment probe:

- Route read-only diagnosis to `sas cybernet Probe HOST` or its alias `sas network HOST`.
- Route authorized product deployment to `sas cybernet Deploy HOST`; that command owns the same readiness gate before mutation and must continue in the same transaction when it passes.
- The deployment readiness transport is fixed to `kerberos_smb_task` and follows DNS -> CIFS ticket -> TCP 445 -> `ADMIN$` authorization -> TCP 135 -> Schedule service -> one reserved nonexistent task query.
- A failed earlier dependency suppresses later observations.
- Never substitute Naabu, Nmap, a subnet scan, the general Cybernet key-port profile, WinRM ports, or `auto` transport discovery for software deployment readiness.
- The standalone readiness probe is diagnostic and read-only. It must not become a repeated prerequisite loop before an already authorized deployment.
- Required live readiness state: `CYBERNET_DEPLOYMENT_READINESS_READY` with transport classification `kerberos_smb_task_ready` and `target_mutation_performed=false`.
- Required full deployment state remains `CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED`; readiness is admission, not completion.
- After a terminal crash or missing console output, route first to `sas evidence` rather than repeating the probe or deployment.

## Change process

1. Read `docs/OPERATIONAL_POSTURE.md`, `docs/LOW_NOISE_SURVEY_DOCTRINE.md`, `docs/SOFTWARE_DEPLOYMENT_LOW_NOISE.md`, `survey/README.md`, and the relevant survey/profile docs.
2. Resolve the actual question before choosing a tool: general survey population/reachability or one-target software deployment readiness.
3. Use the language-runtime skill to choose the actual implementation surface; preserve the Windows PowerShell technician surface for Cybernet deployment readiness and Bash-first doctrine for suitable new general survey work.
4. Make the smallest change without broadening targets, ports, rates, retries, transports, or mutation posture.
5. Validate with scoped, non-live checks unless the user requested an approved field run.
6. Report the exact proof ceiling of fixture, dry-run, packet, readiness, deployment, or field evidence.
