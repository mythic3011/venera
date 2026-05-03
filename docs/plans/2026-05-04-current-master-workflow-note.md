# Current Master Workflow Note

Date: 2026-05-04
Scope: workflow hygiene only
Behavior change: none

## Authority

Working branch authority for integration is local `master`, not `.worktrees/v0-next-queue`.

Reason:

- `feature/v0-next-queue` is fully contained in local `master` (`172 0` divergence)
- queue worktree currently has local uncommitted drift and is not a clean baseline

## Integration Workflow (Current)

Follow serial integration queue rules already defined in:

- `docs/plans/old/2026-04-30-venera-next-core-rewrite-plan.md` (`Integration Queue`)
- `docs/plans/old/2026-04-30-unified-comic-detail-local-remote-implementation-plan.md` (`Multi-Agent Execution Contract`)

Operational steps:

1. refresh from accepted base (`master`)
2. run lane-local tests
3. run `flutter analyze`
4. inspect diffs for ownership leaks
5. merge one lane at a time
6. rerun affected cross-lane tests

## Hygiene Guardrails

- Keep docs/state in tracked tree (`docs/plans/**`), not only in `.worktrees/**`
- Do not treat dirty worktrees as workflow authority snapshots
- Keep lanes isolated by file ownership and commit scope
