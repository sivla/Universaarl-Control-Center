---
name: run-bc-basic-simulation
description: Execute or review the complete repository-based synthetic Business Central Basic implementation project. Use for synthetic customer data, setup, P2P, O2C, payments, reconciliation, inventory, month-end, VAT preview, UAT, training, cutover, go-live rehearsal, hypercare, restart, handover, deliverables, and simulation evidence without active Business Central access.
---

# Run BC Basic Simulation

1. Read the project `AGENTS.md`, active OpenSpec change, project plan, deliverables, UAT catalog, decision register, data package, source register, and branch index.
2. Work only in the BC Basic repository when that repository is the active project. From the control center, inspect commit-bound evidence and delegate the block to the BC Basic task.
3. Keep all data synthetic. Never access Business Central, banks, ELSTER, email, or live customer systems unless a later explicit project-specific authorization changes the scope.
4. Execute phases as file-level rehearsals, not plans. For each use case record inputs, expected BC steps, documents and entries, account/VAT/inventory effects, control totals, defects, corrections, retests, and synthetic acceptance.
5. Maintain honest states such as `synthetic-complete`, `simulated-complete`, and `synthetisch-abgenommen`. Never claim real execution, production, or customer acceptance.
6. Use official Microsoft Learn sources where relevant. Separate documented BC behavior, project assumption, synthetic value, and unresolved German localization or tax question.
7. Keep `exports/project-data/v1/index.yaml` as the only current Twin allowlist contract. Include every Twin-visible evidence file in the same normal project commit; do not create an A/B manifest-only commit.
8. Deliver one coherent phase commit with relevant tests plus one total check, empty `REVIEW.md`, and a clean worktree. Do not push, merge, tag, or release from the project task.

Completion requires data, all business processes, UAT, training, cutover, go-live rehearsal, hypercare, restart, closure, and handover to possess concrete synthetic evidence.
