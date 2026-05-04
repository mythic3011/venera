# Local Filesystem Reconcile (Master)

This plan tracks three independent implementation lanes with separate review gates:

1. `I-local-filesystem-reconcile-1` Passive browse hide for missing payloads.
2. `I-local-filesystem-reconcile-2` Explicit cleanup for eligible orphan local-library rows.
3. `I-local-import-repair-1` Duplicate import preflight and missing-payload repair.

Constraints:
- DB remains canonical authority.
- Browse-time behavior is non-destructive.
- Cleanup is explicit only.
- Import repair is fail-closed on conflicts.
