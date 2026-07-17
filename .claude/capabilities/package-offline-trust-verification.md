# Package Offline Trust Verification Capability

## Contract

Observe and gate package trust with cache-only Windows Authenticode evaluation and an explicit reviewed policy. Trust approval advances only to the qualification gate.

## Operation boundary

- Consume the static result and optional reviewed trust policy.
- Re-verify source hashes and reject reparse-point chains.
- Distinguish valid, not signed, unsupported SIP, invalid digest, untrusted chain, expired, and verification-error states.
- Preserve unsigned-wrapper exceptions for genuine unsigned or unsupported-wrapper surfaces only.
- Block signed files that attempt unsigned exceptions and keep invalid signatures blocked.

## Authority

- `harness/api/package-trust-verification-skill.json`
- `scripts/Invoke-SasPackageTrust.ps1`
- `tools/package-analysis/SasPackageTrustInterop.cs`
- `schemas/harness/package-trust-policy.schema.json`
- `schemas/harness/package-trust-verification-result.schema.json`
- `docs/PACKAGE_TRUST_VERIFICATION.md`

## Forbidden

Never perform online revocation, execute package code, auto-approve observed signers, or claim application approval from Authenticode validity alone.

## Used by

- `.claude/skills/package-static-analysis/SKILL.md`
