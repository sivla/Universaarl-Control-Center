---
name: verify-project-twin
description: Implement or verify Project Twin as a German, strictly read-only view of the latest validated BC Basic development-branch commit. Use for the branch-index contract, commit pinning, safe Git-blob reads, allowlist and reference checks, fail-closed cases, UI behavior, desktop and mobile browser evidence, or Twin release readiness.
---

# Verify Project Twin

1. Read Twin `AGENTS.md`, active OpenSpec change, adapter, registry, tests, and the commit-bound BC Basic index.
2. Resolve the allowed BC Basic branch once to a full SHA. Read only `exports/project-data/v1/index.yaml` and its positively listed Git blobs from that SHA. Never read the producer worktree or write back.
3. Ignore legacy `snapshot-manifest.json`, `producerCommitSha`, Parent-A, and manifest-only-diff rules in branch mode.
4. Validate repository and branch identity, index contract fields, project identity, safe unique IDs and paths, required blobs, references, and available digests. Fail closed in German.
5. Accept producer-defined UABC IDs; do not impose an unrelated consumer regex. Continue to reject traversal, absolute paths, URIs, duplicate IDs, missing evidence, and branch movement after pinning.
6. Keep `.env.local` unread and unchanged. Supply source path and branch only through a temporary sanitized process environment.
7. Show BC Basic as the only customer project, including status, phases, work packages, decisions, risks, and simulation evidence. Present evidenced synthetic customer approvals, UAT, cutover GO, go-live rehearsal, hypercare, restart, closure, and handover as passed simulation gates, not external blockers. State clearly that no live BC or productive customer activity occurred.
8. Render the complete project story: offer versions and actuals, populated Confluence-style page tree, ticket board and ticket detail with status history, worklogs, evidence, working comments and closing comments, chronological timeline from offer through final hypercare, BC playthrough sessions and ledger entries, daily hypercare status, handover and cross-project findings. Preserve bidirectional navigation across source IDs.
9. Prove the positive desktop and mobile views plus negative contract cases with deterministic tests and screenshots under `output/playwright/`.
10. Require relevant tests, one `npm run check`, German gate, empty `REVIEW.md`, clean worktree, and one coherent local commit. Do not push from the project task.
