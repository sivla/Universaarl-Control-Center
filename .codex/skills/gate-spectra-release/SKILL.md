---
name: gate-spectra-release
description: Plan, validate, promote, and independently verify one Spectra release at a time. Use for release scope, candidate manifests and digests, workspace-validator gates, PR and merge readiness, annotated tags, prerelease publication, or post-release verification while preventing scope drift and invented versions.
---

# Gate Spectra Release

1. Establish the published base release and exactly one next version. Keep scope, non-scope, and acceptance criteria explicit; do not start later release work in the same cycle.
2. Read Spectra `AGENTS.md`, the single active OpenSpec change, release plan, candidate manifest, checksums, and current branch state.
3. Verify candidate commit, payload file count, every blob size and SHA-256, bundle digest, schema parity, product contract, workspace fixtures, OpenSpec strict, and clean worktree.
4. A candidate remains `PENDING`: no `source_commit`, tag, or published-release claim.
5. Promote only after an independent gate passes. Finalize the manifest with the correct source commit, rerun all gates, use a normal PR and merge, then create an annotated `spectra-v<SemVer>` tag and publish a non-draft prerelease.
6. Never force-push, bypass hooks, invent evidence, mix customer data into Spectra, or add out-of-scope features.
7. After publication, independently verify tag object, peeled commit, manifest source ancestry, all payload blobs, digest, release URL, prerelease state, and clean worktree.
8. End with either a proven release or an exact no-go blocker. Only then define the next release scope.
