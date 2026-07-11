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
7. Show BC Basic as the only customer project, including status, phases, work packages, decisions, risks, and simulation evidence.
8. Prove the positive desktop and mobile views plus negative contract cases with deterministic tests and screenshots under `output/playwright/`.
9. Require relevant tests, one `npm run check`, German gate, empty `REVIEW.md`, clean worktree, and one coherent local commit. Do not push from the project task.
