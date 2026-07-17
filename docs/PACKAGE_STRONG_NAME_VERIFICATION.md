# Package Strong-Name Verification

## Purpose

SysAdminSuite can cryptographically verify CLR strong-name integrity for managed PE assemblies without executing package code and without treating the result as Authenticode publisher trust.

The static and semantic lanes can observe a strong-name flag or signature blob. Presence is not integrity. This producer:

1. re-verifies every source hash from the static inventory;
2. detects managed CLR assemblies;
3. extracts the Assembly public-key blob;
4. hashes the PE image with CLR strong-name exclusions;
5. verifies the RSA strong-name signature offline;
6. emits a canonical ignored result that the VM qualification profile may reference.

## Canonical surfaces

- Producer: `tools/package-analysis/verify_dotnet_strong_name.py`
- Operation contract: `harness/api/package-strong-name-verification-skill.json`
- Result schema: `schemas/harness/package-strong-name-verification-result.schema.json`
- Windows entrypoint: `scripts/Invoke-SasPackageStrongNameVerification.ps1`
- Bash entrypoint: `scripts/invoke-sas-package-strong-name-verification.sh`
- Contracts: `Tests/survey/test_package_strong_name_verification_contracts.py`

## Validation command

```powershell
python .\Tests\survey\test_package_strong_name_verification_contracts.py
```

Operator run:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-SasPackageStrongNameVerification.ps1 `
  -InputPath .\path\to\package `
  -BaseResult .\survey\output\package_static\package_analysis.json `
  -OutputRoot .\survey\output\package_strong_name\run-1
```

```bash
bash scripts/invoke-sas-package-strong-name-verification.sh \
  --input ./path/to/package \
  --base-result ./survey/output/package_static/package_analysis.json \
  --output ./survey/output/package_strong_name/run-1
```

## Status meanings

| Status | Meaning |
|---|---|
| `verified` | Managed assembly public key and strong-name signature cryptographically match. |
| `unsigned` | Managed assembly has no strong-name material. |
| `delay_signed` | Strong-name reservation exists but the signature blob is empty/zero. |
| `invalid` | Strong-name material is present but the signature does not match the image. |
| `unsupported` | Managed assembly uses a strong-name algorithm this producer does not verify. |
| `failed` | Parsing or hash continuity failed for a listed source. |
| `not_applicable` | File is not a managed CLR PE. |

Aggregate `overall_status` maps unsigned and delay-signed managed assemblies to `unproven` so the qualification gate cannot treat them as complete.

## Proof ceiling

The highest proof is `clr_strong_name_integrity`.

This lane does **not** prove:

- Authenticode publisher trust;
- online revocation freshness;
- MSI/MST decode completeness;
- exact SAPIEN payload recovery;
- installer success;
- application behavior;
- AutoLogon or physical Cybernet acceptance.

A verified strong name clears only the managed-code strong-name evidence gate when the qualification profile references this canonical result.
