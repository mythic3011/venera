# v0-next-queue Archive Note

Date: 2026-05-04
Scope: workflow hygiene only
Behavior change: none

## Status

`feature/v0-next-queue` is a historical/stale workflow lane.

Verified snapshot:

- local `master` HEAD: `31a56c3`
- `feature/v0-next-queue` HEAD: `18448ef`
- divergence (`master...feature/v0-next-queue`): `172 0`

Interpretation:

- queue lane has `0` unique commits
- local `master` already contains all queue-lane commits and additional work

## Archival Decision

Do not use `.worktrees/v0-next-queue/**` as active planning or integration authority.

Use committed docs under `docs/plans/old/**` as historical records:

- `docs/plans/old/2026-04-30-venera-next-core-rewrite-index.md`
- `docs/plans/old/2026-04-30-venera-next-core-rewrite-plan.md`
- `docs/plans/old/2026-04-30-unified-comic-detail-local-remote-architecture.md`
- `docs/plans/old/2026-04-30-unified-comic-detail-local-remote-implementation-plan.md`
- `docs/plans/old/lane-c-phase1-minimal-runtime-core.md`
- `docs/plans/old/source-runtime-account-request-policy.md`

## Operator Rule

If a queue-worktree doc and a tracked `docs/plans/**` doc disagree, prefer tracked `docs/plans/**` plus current branch evidence.
