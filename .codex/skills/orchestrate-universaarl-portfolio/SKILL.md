---
name: orchestrate-universaarl-portfolio
description: Orchestrate BC Basic, Spectra, Project Twin, and the Universaarl control center from evidence-backed handoffs. Use when defining or adjusting project goals, checking progress across projects, assigning the next large delivery blocks, assessing integration or release readiness, or keeping all projects moving toward a working end-to-end state.
---

# Orchestrate Universaarl Portfolio

1. Read the current repository `AGENTS.md` and `portfolio.state.json`.
2. Inspect the actual project-task status and latest completed handoffs. Treat commits, trees, tests, clean worktrees, screenshots, tags, and releases as evidence; do not treat prompts as delivery.
3. Keep exactly these roles:
   - Spectra: reusable product contract, release by release.
   - BC Basic: customer source of truth and full synthetic project execution.
   - Project Twin: read-only view of a validated BC Basic branch commit.
   - Control center: lean orchestration, independent validation, and release assessment.
4. Identify one largest gap per project and assign one substantial, outcome-focused delivery block. Avoid microtasks and parallel OpenSpec changes within a project.
5. Preserve repository boundaries. From the control center, never edit target repositories; steer their existing project tasks instead.
6. After each handoff, verify branch, full commit SHA, tree, tests, `REVIEW.md`, worktree state, and cross-project contract before updating `portfolio.state.json`.
7. Use the current contract: branch for ongoing BC Basic development, commit for validated state, tag for release. Do not reintroduce the legacy A/B manifest-only sequence.
8. Keep the overall goal active until BC Basic is fully simulated, Spectra has the required published release, and Twin visibly renders the latest validated BC Basic commit fail-closed.

Report only current outcomes, blockers, next blocks, and evidence identifiers.
