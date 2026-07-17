# Resume Matcher live acceptance checklist

Use this checklist only after the deployment profile and fixture contracts pass.
It is a workstation runtime gate, not a substitute for CI.

## Preconditions

- Run from a clean SysAdminSuite branch containing the Resume Matcher service.
- Use the WSL distribution where Resume Matcher is installed.
- Confirm the provider key is already saved through the Resume Matcher Settings UI.
- Keep personal resumes and job descriptions out of the acceptance run.
- The generated PDF is a sanitized fixture stored under the ignored state root.

## Non-billable acceptance

From Windows PowerShell:

```powershell
pwsh -File .\scripts\Test-SasResumeMatcherLiveAcceptance.ps1 -Distro Ubuntu
```

From WSL or Linux Bash:

```bash
bash scripts/test-sas-resume-matcher-live-acceptance.sh
```

This proves the pinned runtimes, Resume Matcher browser fallback, sanitized PDF
export, backend health, frontend page identity, and presence of a saved provider
configuration. It does not send an LLM request.

## Provider-health acceptance

Run only when one bounded provider request and its possible usage charge are
acceptable:

```powershell
pwsh -File .\scripts\Test-SasResumeMatcherLiveAcceptance.ps1 `
  -Distro Ubuntu `
  -RequireProviderHealth
```

or:

```bash
bash scripts/test-sas-resume-matcher-live-acceptance.sh --require-provider-health
```

The result records only the provider name, model name, and health boolean. It
never records the API key or model output.

## Required success evidence

The result JSON must report:

- `operation: accept`
- `outcome: success`
- `lifecycle_state: accepted`
- backend and frontend health observed
- frontend content observed
- browser launch observed
- sanitized PDF export observed with nonzero size and SHA-256
- provider configured
- `acceptance_completed: true`

When provider health was explicitly required, it must also report
`provider_health_observed: true`.

## Failure handling

- `provider-not-configured`: configure and save the provider in the Settings UI.
- `startup-timeout`: inspect the repo-owned tmux backend and frontend windows.
- `frontend-content-missing`: verify that port 3000 belongs to Resume Matcher.
- `provider-health-failed`: use Resume Matcher's Settings connection test and
  review provider balance/model availability without copying secrets into logs.
- `validation-failed`: run the read-only Validate action and inspect Python,
  Node, frontend dependencies, browser fallback, and the sanitized PDF path.

Do not edit the result to force acceptance. Correct the failed layer and rerun
the same command.
