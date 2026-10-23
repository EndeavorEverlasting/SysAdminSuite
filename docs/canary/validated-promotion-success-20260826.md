# Validated Promotion Success Canary

This documentation-only file is a provider-runtime canary for the SysAdminSuite validated promotion pipeline.

Expected behavior:
- the exact PR source head, current `main` base, and GitHub synthetic merge candidate are pinned;
- promotion contracts, canonical harness E2E, and application E2E must pass on that exact merge candidate;
- the serialized writer may advance `main` only to the exact validated synthetic merge object;
- post-promotion proof must show source-head and merge-candidate ancestry containment plus GitHub merged-PR state.

This canary does not authorize or perform live target, protected workstation, device, printer, Active Directory, package-share, or production mutation.
