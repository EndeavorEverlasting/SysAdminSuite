# Outcome-Driven Execution

## Trigger

Use this harness-scoped skill when the requested result is an artifact, build, runtime, repair, or deployment and the work contains validators, dry runs, plans, preflights, or other intermediate gates that could otherwise become artificial stopping points.

Do not route this skill through the root `.claude/skills` governance router. It is a harness execution procedure used after the normal repository route is already selected.

## Required inputs

- repository root and current branch/worktree;
- requested goal in plain language;
- owned and forbidden scope;
- explicit target when the selected workflow needs one;
- target-mutation or network authorization when required;
- proof ceiling and any genuine external blocker already known.

## Procedure

1. Read `harness/api/harness-outcome-registry.json` and the command, validator, and artifact registries.
2. Resolve the requested goal before executing an intermediate validator.
3. Select the smallest command chain that can prove that goal.
4. Treat validators, dry runs, plans, preflights, and harmless live certs as admission gates.
5. Require every successful admission gate to emit or resolve a registered artifact. A green console message by itself is insufficient.
6. If the requested goal remains unproven and the registry names a same-turn continuation, execute it immediately when it is safe, authorized, dependency-satisfied, and available to the agent.
7. Do not hand a safe executable continuation back to the operator merely because a test passed.
8. Preserve explicit confirmation, credentials, physical access, protected runtime, and target-mutation gates. Those are real blockers, not excuses to bypass.
9. On failure, produce or preserve the owning artifact/evidence, classify the smallest failed boundary, repair inside owned scope when possible, and rerun that boundary.
10. Stop only with one of the terminal outcomes allowed by the outcome registry: artifact created, build artifact created, runtime started, product deployed, or blocked with an exact actionable external gate.

## Forbidden stopping patterns

- `tests passed` with the requested deployment/build/artifact still unproven;
- `here is the next command` when the agent can safely run that command itself;
- `send me the logs` when the repo already produced a canonical artifact the agent can resolve;
- `wait for CI` as the final action when another safe local/remote proof step is available;
- asking the operator to repeat inspection, path resolution, branch selection, or log collection the harness can perform;
- treating a dry run, plan, launcher start, process presence, or command acknowledgment as the requested product outcome.

## Expected outputs

- requested goal;
- ordered command IDs executed;
- admission artifacts produced;
- terminal outcome;
- canonical final artifact or deployment evidence path;
- exact blocker owner/action/artifact only when a real external gate remains;
- proof ceiling actually reached.

## Proof ceiling

This procedure enforces progress through repository-owned executable gates. It does not manufacture authorization or elevate static/dry-run evidence into runtime or deployment proof.
