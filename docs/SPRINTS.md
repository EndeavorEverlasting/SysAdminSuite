# Sprint Working Rules

Implementation sprints should produce repository progress: tracked file changes, validation, and Git continuity when available.

Planning and next-agent prompts are closeout artifacts, not substitutes for implementation work.

Before starting new work, inspect existing docs, scripts, tests, contracts, naming conventions, and output paths.

Keep changes bounded. Reuse repo patterns. Avoid unrelated rewrites. Do not create dummy commits or duplicate pull requests.

## Enforcement

The sprint rules are enforced by `Tests/survey/test_sprint_working_rules_contracts.py` and should be run directly when this document changes.

Local hook coverage is provided by `.githooks/pre-push`, which runs the sprint working rules contract before push after the local harness hooks are installed.

Recommended next SysAdminSuite sprint queue:

1. Target Reduction Planner
2. English Report Renderer
3. Canonical Run Context
4. Survey Workflow Specs
5. End-to-End Harness Validator
6. Local MCP Server Skeletons
7. Standard CMD and PowerShell Renderers
8. Location/Subnet Candidate Planner
9. Dashboard Serial Controls Integration
10. Executor Guardrail Expansion
