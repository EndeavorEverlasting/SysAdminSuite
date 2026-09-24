# External Field Evidence Boundary

## Purpose

SysAdminSuite may be used alongside operator-managed documents, screenshots, meeting notes, ticket exports, or other field evidence stored outside the repository.

Those materials can help a human review an issue or pull request, but they are **not a repository dependency**.

## Provider-neutral rule

SysAdminSuite must not require, discover, authenticate to, crawl, mount, synchronize, or infer a specific cloud-storage provider or personal account.

Repository code, tests, launchers, and validation must remain functional when no external document exists.

## Issue and pull-request use

An authorized operator may manually attach or link external evidence to an issue or pull request when it helps human review.

Use external material for context such as:

- technician tutorials or quick-start guides;
- screenshots and photos;
- meeting notes;
- site-specific values;
- vendor correspondence;
- acceptance notes.

The repository may state that **external evidence is available** or request a human review of it. It must not encode a personal cloud account, private folder hierarchy, provider-specific file ID, or private URL as a runtime requirement.

## Source-control boundary

Do not commit:

- credentials, passwords, PINs, tokens, or private keys;
- personal cloud-account identifiers;
- private external-workspace URLs or folder IDs;
- live site/device values unless a repository contract explicitly requires a sanitized fixture;
- restricted screenshots or raw field exports.

Use synthetic examples and repository-local ignored evidence for executable contracts.

## Authority boundary

External documents can be authoritative for live field context while repository source remains authoritative for reusable logic.

That split is valid only when it is explicit:

- reusable commands, scripts, validators, and contracts -> repository;
- live site/device context and restricted human evidence -> operator-controlled external workspace;
- issue/PR -> human coordination and acceptance ledger;
- runtime -> never depends on an external document merely existing.

## Acceptance

A field workflow is not accepted just because an external document describes it. Acceptance must still be grounded in the repository's own contracts plus the required human/runtime evidence for that workflow.
