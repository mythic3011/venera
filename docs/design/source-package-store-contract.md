# Source Package Store Contract

## Purpose

This document defines `PackageStore` as the durable authority boundary for verified source package artifacts.

`PackageStore` is the middle durable boundary in the lifecycle commit order defined by [`source-package-artifact-lifecycle.md`](./source-package-artifact-lifecycle.md):

`verified artifact -> package store commit -> source_platform mutation`

## Scope

This is a contract-only design slice. It defines behavioral requirements and failure semantics for durable artifact persistence and read surfaces.

It does not define runtime implementation details, storage engines, or TypeScript interfaces.

## Responsibilities

`PackageStore` must:

- Persist verified artifact metadata and content as durable artifact authority.
- Commit artifact state atomically, with no durable partial install state.
- Expose a read contract for installed artifact metadata required by orchestration.
- Support deterministic orphan marking and cleanup after downstream mutation failure.

## Failure Semantics

- Commit failure means no durable partial install state is observable.
- If `source_platform` mutation fails after package store commit, artifact state must be transitioned to orphaned/unreferenced state and routed to deterministic cleanup.
- Orphan cleanup must be auditable through explicit state and cleanup-path signaling at contract level.
- Orphaned artifacts must not be loadable or executable as active source packages.
- Read output is evidence for orchestration only; it must not be interpreted as source-identity authority.

## Non-responsibilities

`PackageStore` must not own:

- Source identity arbitration across existing `source_platform` state.
- Integrity verification logic (owned by verifier boundary).
- Source execution, sandbox creation, or runtime loading behavior.

Behavioral invariants:

- `PackageStore` may store `packageKey`, `providerKey`, `version`, and `archiveSha256` as metadata, but it must not decide whether they are compatible with an existing `source_platform`.
- `PackageStore` read output is evidence for orchestration, not authority for source identity.

