# AgentSwitchboard GNHF Adoption

SysAdminSuite consumes AgentSwitchboard's versioned GNHF request/result boundary without copying its schemas, compiler, desktop launcher, model routing, workstation installers, or runtime evidence implementation.

## Authority boundary

| Concern | Authority |
|---|---|
| SysAdminSuite objective, scope, registered workflow, validators, result ingestion, and sprint capsule | SysAdminSuite |
| Regular-request, compiled-prompt, launch-request, and runtime-result schemas | AgentSwitchboard |
| Prompt compilation, local desktop launch, workstation configuration, and runtime evidence | AgentSwitchboard |
| External compatibility version, commit, schema blobs, and entrypoint blob | `harness/api/agentswitchboard-gnhf-external-contract.json` |

The current consumer pin supports external schema version 1 at the exact AgentSwitchboard source commit recorded in that manifest. Unavailable authority, a different schema version/blob, or an unknown result kind fails closed. Updating the pin requires re-running the focused compatibility fixtures and validators; it is not automatic trust of a moving branch.

## Deterministic signals

| Signal | Result | Execution boundary |
|---|---|---|
| `generate a good night have fun prompt` | One compiled prompt plus validation | Compile only; never `-Run` |
| `run this GNHF sprint locally` | AgentSwitchboard runtime delegation | Requires explicit local authorization, availability, clean attached target, and one Git mode |
| `configure my GNHF environment` | Existing AgentSwitchboard environment Plan | Apply and authentication remain operator-owned |
| `execute this registered workflow overnight` | Registered workflow delegation | Requires workflow registration, explicit execution authorization, caps, and deterministic stop conditions |

Unknown or conflicting intent returns to the repository-sprint route for evidence-led classification.

## Local command boundary

After the desktop thread has written and validated the request and compiled prompt to ignored local paths, Plan uses the external entrypoint:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$env:AGENTSWITCHBOARD_ROOT\tooling\gnhf\Invoke-CursorGnhfSprint.ps1" -RequestPath "$env:SAS_GNHF_REQUEST_PATH" -CompiledPromptPath "$env:SAS_GNHF_COMPILED_PROMPT_PATH" -TargetRepo "$env:SAS_REPO_ROOT" -PlanOnly
```

Only an explicit local-execution request replaces `-PlanOnly` with `-Run`. SysAdminSuite does not provide a second launcher or workstation installer.

## Failure and proof contract

- Missing local permission is rejected as `LOCAL_EXECUTION_PERMISSION_REQUIRED`.
- Missing AgentSwitchboard authority is blocked as `AGENTSWITCHBOARD_UNAVAILABLE`.
- A version difference is rejected as `EXTERNAL_SCHEMA_VERSION_MISMATCH`.
- Dirty, detached, or conflicting Git state remains non-success and is delegated to the external runtime's typed result.
- Returned failed-work references and any upstream preservation gap are carried forward; a failed worktree is not promised to exist.
- Process start or exit is insufficient. Successful ingestion requires external artifact and commit proof.
- The sprint capsule reuses `agent_sprint_capsule.generate` and preserves the returned proof ceiling. Contract fixtures do not prove live GNHF, provider quality, workstation behavior, target behavior, or operator acceptance.

## Focused validation

```text
python3 Tests/survey/test_agentswitchboard_gnhf_prompt_adoption_contracts.py
python3 Tests/survey/test_agent_instruction_factoring_contracts.py
python3 Tests/survey/test_agent_capability_manifest_contracts.py
python3 Tests/survey/test_agent_routing_manifest_contracts.py
python3 Tests/survey/test_agent_sprint_capsule_contracts.py
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/validate-ai-layer.ps1
```
