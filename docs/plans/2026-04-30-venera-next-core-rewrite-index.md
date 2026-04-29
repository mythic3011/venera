# Venera Next Core Rewrite Index

## Purpose

This is the index for the active Venera Next rewrite documentation set.

Use this doc to answer two questions quickly:

1. which rewrite plan is canonical
2. which older docs are still useful and which are legacy appendix material

## Canonical Docs

Primary execution and boundary authority:

- `docs/plans/2026-04-30-venera-next-core-rewrite-plan.md`

Supporting architecture:

- `docs/plans/2026-04-30-unified-comic-detail-local-remote-architecture.md`

Supporting implementation backlog:

- `docs/plans/2026-04-30-unified-comic-detail-local-remote-implementation-plan.md`

Active runtime-side supporting lane:

- `docs/plans/lane-c-phase1-minimal-runtime-core.md`
- `docs/plans/source-runtime-account-request-policy.md`

## Legacy Appendix Docs

Useful as historical UI notes only:

- `docs/plans/2026-04-28-local-comic-management-design.md`
- `docs/plans/2026-04-28-local-comic-management-implementation.md`

These documents are not active domain-authority plans.

## Rewrite Boundary Summary

- old core is being replaced, not repaired
- old local/history/favorite/source flows may only be touched for extraction or buildability
- `data/venera.db` is the canonical domain database
- no runtime fallback reads from `local.db`, `history.db`, `local_favorite.db`, or hidden JSON domain state
- no dual-write compatibility layer
- target detail surface is `ComicDetailPage(comicId)`
- raw internal IDs are diagnostics-only, not user-facing primary labels

## Immediate Execution Focus

Stay in V0:

1. local import -> canonical tables
2. source-default page-order creation
3. unified detail route by `comicId`
4. reader open path from canonical local comic state
5. first `ReaderDebugSnapshot`
6. remove user-facing dependency on raw legacy IDs

Parallel UX track after authority cutover starts:

- search/discovery becomes a shared local/remote surface
- source providers/data sources become a shared discovery model
- detail page becomes a shared local/remote metadata-first and scan-friendly surface
- comic-source handling becomes a shared source panel, not a separate UI world
- manage surface becomes a shared comic editor, not a raw ID list
- page reorder becomes thumbnail-first, not filename-first
- export moves into a dedicated workflow

Core terminology lock:

- local and remote are both `DataSource`
- `Comic` is canonical identity
- search results are `DataSourceCandidate`, not provenance
- confirmed comic-to-source relationships are `ComicSourceLink` /
  `ProvenanceLink`
- user tags/notes/favorites/custom order are `UserOverlay`

Layering lock:

- UI knows `Comic + capabilities`, not local/remote as separate worlds
- application services are the orchestration boundary
- domain does not depend on Flutter or raw storage details
- persistence/integration does not decide user-facing workflow policy
- every layer has structured diagnostics, but each layer logs only what it owns

Package lock:

- packages are allowed to reduce plumbing
- packages are not allowed to define domain policy
- add core infra packages first, evaluate optional helpers later
