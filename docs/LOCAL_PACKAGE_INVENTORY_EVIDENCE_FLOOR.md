# Local Package Inventory Evidence Floor

The local package inventory lane is read-only evidence collection. It does not approve or execute an installer.

## Required operator input

Real scans require an explicit `-ScanPath`. The scanner has no machine-local default. The supplied root is used only during the scan and is emitted as the redacted identity `operator-local-reference`.

```powershell
pwsh -NoProfile -File .\scripts\Get-SasLocalPackageInventory.ps1 `
  -ScanPath <gitignored-operator-local-reference-root> `
  -OutputPath <approved-ignored-output-path>
```

Fixture proof is separate:

```powershell
pwsh -NoProfile -File .\scripts\Get-SasLocalPackageInventory.ps1 -FixtureOnly
```

## Evidence boundaries

The scanner may record:

- paths relative to the supplied root;
- file size and SHA-256;
- Authenticode status and signer when present;
- file-version metadata;
- selected MSI property-table values through read-only access;
- adjacent configuration filenames;
- bounded behavior indicators from text files;
- a conservative environment classification.

The scanner must not record the supplied absolute scan root, a drive-qualified path, a UNC target, a parent-traversal path, credentials, or configuration values.

## Installer arguments

Observed switches and conventional MSI flags are not approved installer arguments. Inventory output keeps `installer_arguments` null until a separate authorized package-intake workflow records vendor-supported arguments and their evidence reference.

A package with missing argument evidence remains `blocked_missing_evidence` unless its observed mutation class requires an even stricter environment:

- services, account changes, or reboot behavior: `requires_reboot_vm`;
- AutoLogon behavior: `requires_physical_cybernet`.

## Proof ceiling

Fixture output and static contracts prove redaction, schema shape, and fail-closed classification. They do not prove package identity, vendor arguments, installation, application launch, Cybernet compatibility, or AutoLogon runtime behavior.
