# Package CLR Strong-Name Verification Capability

## Contract

Cryptographically verify CLR strong-name integrity for managed PE assemblies after static inventory hash continuity is proven. Strong-name validity advances only the qualification evidence gate for managed code.

## Operation boundary

- Consume the static result and re-verify every source hash.
- Detect managed CLR assemblies and classify unsigned, delay-signed, verified, invalid, unsupported, and failed states.
- Extract the Assembly public-key blob and verify the strong-name signature offline.
- Emit `package_strong_name_verification.json` and an English operator report under an ignored output root.
- Keep Authenticode publisher trust, online revocation, MSI decode, SAPIEN recovery, and runtime behavior as separate lanes.

## Authority

- `harness/api/package-strong-name-verification-skill.json`
- `tools/package-analysis/verify_dotnet_strong_name.py`
- `schemas/harness/package-strong-name-verification-result.schema.json`
- `docs/PACKAGE_STRONG_NAME_VERIFICATION.md`

## Forbidden

Never execute package code, evaluate Authenticode publisher trust, perform online revocation, or claim application, install, or Cybernet proof from a verified strong name.

## Used by

- `.claude/skills/package-static-analysis/SKILL.md`
