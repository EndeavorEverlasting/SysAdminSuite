# Package Trust Verification

SysAdminSuite can bind the static package inventory to an offline Windows Authenticode and approval-policy gate without executing package code.

## Why this is separate from static analysis

The static analyzer can observe a PE certificate table or CLR strong-name material, but presence is not cryptographic trust. The trust lane:

1. consumes `package_analysis.json` from the canonical static analyzer;
2. rejects unsupported or higher-proof base results;
3. re-verifies every source SHA-256;
4. rejects source files and intermediate directories that are reparse points;
5. evaluates embedded Authenticode through `WinVerifyTrust`;
6. forces cache-only URL retrieval and disables online revocation checking;
7. extracts the signer identity from the WinTrust provider state;
8. evaluates an explicit hash-bound signer or unsigned-package policy;
9. emits a deployment disposition without launching the package.

## Proof levels

The lane distinguishes:

- **observation** — signature and signer evidence is collected, but deployment is not approved;
- **offline Authenticode policy** — embedded signature integrity, local Windows trust, exact hash, and explicit policy are evaluated;
- **online revocation** — not performed by this lane;
- **strong-name cryptographic verification** — not performed by this lane;
- **runtime proof** — requires a separate disposable-VM or physical-device lane.

A locally valid signature can still require later online revocation review under the applicable packaging and security process.

## Step 1: run static and semantic analysis

```powershell
.\scripts\Invoke-SasPackageSemanticAnalysis.ps1 `
  -InputPath 'D:\PrivatePackages\Allscripts' `
  -CreateVenv
```

Use the emitted `package_analysis.json` as the trust lane's base result.

## Step 2: observation-only trust inventory

```powershell
.\scripts\Test-SasPackageTrust.ps1 `
  -InputPath 'D:\PrivatePackages\Allscripts' `
  -BaseResultPath '.\survey\output\package_static_analysis\<run>\package_analysis.json' `
  -ObservationOnly
```

Observation mode writes:

- `package_trust_verification.json`
- `package_trust_verification.txt`
- `package_trust_policy.starter.json`

The starter policy is deliberately fail-closed:

- code-bearing files start as `review_required`;
- unlisted code-bearing files are blocked;
- non-code resources may be admitted by exact base-result hash only when `unlisted_noncode_disposition` explicitly says `hash_only_approved`;
- observed signer data is informational and is not automatically approved.

## Step 3: review and approve policy entries

A signed package entry should use `required_valid` and at least one exact signer identity:

```json
{
  "relative_path": "client/setup.exe",
  "expected_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "signature_requirement": "required_valid",
  "approved_signer_thumbprints": ["0123456789ABCDEF0123456789ABCDEF01234567"],
  "approved_signer_subjects": [],
  "approval_reference": "PKG-REVIEW-2026-001",
  "observed_signature_status": "valid",
  "observed_signer_thumbprint": "0123456789ABCDEF0123456789ABCDEF01234567",
  "observed_signer_subject": "CN=Fixture Publisher"
}
```

An internal unsigned wrapper requires an exact hash and an explicit exception reference:

```json
{
  "relative_path": "wrapper/install.cmd",
  "expected_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
  "signature_requirement": "allow_unsigned_explicit",
  "approved_signer_thumbprints": [],
  "approved_signer_subjects": [],
  "approval_reference": "SEC-EXCEPTION-2026-001",
  "observed_signature_status": "not_signed",
  "observed_signer_thumbprint": null,
  "observed_signer_subject": null
}
```

Do not convert an invalid, bad-digest, expired, distrusted, or untrusted signature into an unsigned exception. Those states remain blocked.

## Step 4: run the policy gate

```powershell
.\scripts\Test-SasPackageTrust.ps1 `
  -InputPath 'D:\PrivatePackages\Allscripts' `
  -BaseResultPath '.\survey\output\package_static_analysis\<run>\package_analysis.json' `
  -TrustPolicyPath 'D:\PrivatePolicies\allscripts-trust-policy.json'
```

The command returns success only when every source hash is continuous and every code-bearing file is approved by policy. Possible overall dispositions are:

- `approved_for_vm_intake`
- `review_required`
- `blocked`

Approval means the package may proceed to disposable-VM intake. It does not authorize production deployment.

## Policy rules

The policy is governed by `schemas/harness/package-trust-policy.schema.json`.

- `default_disposition` applies to unlisted code-bearing files and must be `review_required` or `blocked`.
- `unlisted_noncode_disposition` controls hash-only resources and may be `hash_only_approved`, `review_required`, or `blocked`.
- `required_valid` requires a locally valid embedded Authenticode signature and an exact approved signer subject or thumbprint.
- `allow_unsigned_explicit` permits only a genuinely unsigned file pinned by exact SHA-256 and an explicit approval reference.
- `review_required` cannot approve deployment.

## Output evidence

`package_trust_verification.json` records:

- static-result hash;
- re-verified source hashes;
- trust scope per file;
- WinVerifyTrust status code;
- normalized signature status;
- signer subject and thumbprint when available;
- policy identity match;
- per-file disposition and reasons;
- aggregate deployment disposition;
- explicit false proof flags for execution, network, mutation, online revocation, strong-name validation, and runtime behavior.

Absolute package paths are not emitted.

## Safety boundaries

This lane never:

- executes EXE, MSI, script, custom action, service, application, or embedded payload code;
- follows symlinks, junctions, or other reparse points;
- contacts certificate, CRL, OCSP, package, endpoint, target, or VM services;
- claims online revocation freshness;
- treats a CLR strong-name flag or blob as verified strong-name integrity;
- turns a trust result into application, rollback, or Cybernet proof.

## Promotion gate

A package may enter disposable-VM testing only when:

1. static and semantic results are complete;
2. every source hash is continuous;
3. every code-bearing file has an explicit disposition;
4. signed files match approved signer identity;
5. unsigned internal wrappers have documented exceptions;
6. invalid signatures remain blocked;
7. package-specific preflight, logging, acceptance, reboot, and rollback requirements are defined.

## Proof ceiling

The highest proof is `offline_authenticode_policy`. This does not prove online revocation status, strong-name cryptographic validity, supported installer arguments, installation success, application behavior, reboot handling, rollback, Epic or Allscripts integration, AutoLogon, or physical Cybernet compatibility.
