---
name: orchestrate-universaarl-portfolio
description: Orchestrate BC Basic, Spectra, Project Twin, and the Universaarl control center from evidence-backed handoffs. Use when defining or adjusting project goals, checking progress across projects, assigning the next large delivery blocks, assessing integration or release readiness, or keeping all projects moving toward a working end-to-end state.
---

# Orchestrate Universaarl Portfolio

1. Read the current repository `AGENTS.md` and `portfolio.state.json`.
2. When defining, expanding, or adjusting a project goal, read `references/portfolio-goal-contract.md` completely and use the relevant project section as the minimum operational detail. Do not reduce it to a one-line aspiration.
3. Inspect the actual project-task status and latest completed handoffs. Treat commits, trees, tests, clean worktrees, screenshots, tags, and releases as evidence; do not treat prompts as delivery.
4. Keep exactly these roles:
   - Spectra: reusable product contract, release by release.
   - BC Basic: customer source of truth and full synthetic project execution.
   - Project Twin: read-only view of a validated BC Basic branch commit.
   - Control center: lean orchestration, independent validation, and release assessment.
5. Identify one largest gap per project and assign one substantial, outcome-focused delivery block. Avoid microtasks and parallel OpenSpec changes within a project.
6. Preserve repository boundaries. From the control center, never edit target repositories; steer their existing project tasks instead.
7. After each handoff, verify branch, full commit SHA, tree, tests, `REVIEW.md`, worktree state, and cross-project contract before updating `portfolio.state.json`.
8. Use the current contract: branch for ongoing BC Basic development, commit for validated state, tag for release. Do not reintroduce the legacy A/B manifest-only sequence.
9. Treat synthetic customer approvals, UAT sign-off, cutover GO, go-live rehearsal, hypercare acceptance, restart, closure, and handover as executable simulation gates. They are not external blockers once synthetic evidence proves them. Never claim real customer or productive execution.
10. Enforce the evidence-backed learning loop described in the reference: BC Basic proposes anonymized product candidates, Spectra accepts or rejects them through OpenSpec and releases, BC Basic binds released product versions, Twin reports source, contract, or UI findings to the responsible project, and the control center tracks adoption. Never copy customer evidence or permit direct cross-repository edits.
11. Keep the overall goal active until BC Basic is fully simulated through the end of hypercare with a versioned offer, complete Confluence page tree, complete ticket histories and closing comments, BC playthrough and project timeline; Spectra has the required published contract releases; and Twin visibly renders the latest validated BC Basic commit fail-closed.

Report only current outcomes, blockers, next blocks, and evidence identifiers.
