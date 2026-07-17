# GNHF Prompt Adoption Skill

Use this skill for an explicit request to compile a bounded SysAdminSuite sprint prompt, delegate an authorized local GNHF run, plan GNHF environment configuration, or execute a registered workflow overnight.

## Capability dependencies

- [AgentSwitchboard GNHF Request Construction](../../capabilities/agentswitchboard-gnhf-request-construction.md)
- [AgentSwitchboard GNHF External Contract Validation](../../capabilities/agentswitchboard-gnhf-external-contract-validation.md)
- [AgentSwitchboard GNHF Prompt Compilation Delegation](../../capabilities/agentswitchboard-gnhf-prompt-compilation-delegation.md)
- [AgentSwitchboard GNHF Local Runtime Delegation](../../capabilities/agentswitchboard-gnhf-local-runtime-delegation.md)
- [AgentSwitchboard GNHF Result Ingestion](../../capabilities/agentswitchboard-gnhf-result-ingestion.md)
- [AgentSwitchboard GNHF Sprint Capsule Generation](../../capabilities/agentswitchboard-gnhf-sprint-capsule-generation.md)

## Workflow

1. Classify the exact signal using `harness/api/agent-routing-manifest.json`; conflicting or unknown intent returns to `repository-sprint`.
2. Construct a version-1 regular sprint request from explicit objective, scope, Git context, artifacts, validators, safety constraints, and proof target.
3. Validate the outbound packet against the pinned AgentSwitchboard contract before compilation delegation.
4. For `generate a good night have fun prompt`, stop after one compiled prompt and its validation result; never add `-Run`.
5. For `run this GNHF sprint locally`, require explicit local execution authorization, an available pinned AgentSwitchboard checkout, a clean attached target, and exactly one Git mode before delegating to the canonical external entrypoint.
6. For `configure my GNHF environment`, delegate AgentSwitchboard Plan first; Apply remains separately authorized.
7. For `execute this registered workflow overnight`, require a registered SysAdminSuite workflow plus explicit execution authorization and bounded stop conditions.
8. Validate and ingest the returned result without raising its proof level or proof ceiling, then reuse the existing sprint-capsule operation for handoff compression.

## Outputs

- AgentSwitchboard-compatible regular request;
- compiled-prompt validation result;
- validated delegation result when execution was authorized;
- exact local next command;
- registered sprint capsule when handoff is requested.

## Guardrails

- No target mutation, deployment authority, credentials, machine-local tracked evidence, hidden chat-context dependency, automatic authentication, automatic execution, or proof escalation.
- SysAdminSuite owns repository workflow selection and validation. AgentSwitchboard owns compilation/runtime schemas, workstation setup, launch, and runtime evidence.
- A process exit without required artifact and commit proof is not success.

## Proof ceiling

Local contracts, sanitized fixtures, routing, and delegation compatibility only. Live GNHF, provider, workstation, deployment, or operator-acceptance behavior remains unproven unless separately observed.
