---
name: run-bc-basic-simulation
description: Execute or review the complete repository-based synthetic Business Central Basic implementation project. Use for synthetic customer data, setup, P2P, O2C, payments, reconciliation, inventory, month-end, VAT preview, UAT, training, cutover, go-live rehearsal, hypercare, restart, handover, deliverables, and simulation evidence without active Business Central access.
---

# Run BC Basic Simulation

1. Read the project `AGENTS.md`, active OpenSpec change, project plan, deliverables, UAT catalog, decision register, data package, source register, and branch index.
2. Work only in the BC Basic repository when that repository is the active project. From the control center, inspect commit-bound evidence and delegate the block to the BC Basic task.
3. Keep all data synthetic. Never access Business Central, banks, ELSTER, email, or live customer systems unless a later explicit project-specific authorization changes the scope.
4. Execute phases as file-level rehearsals, not plans. For each use case record inputs, expected BC steps, documents and entries, account/VAT/inventory effects, control totals, defects, corrections, retests, and synthetic acceptance.
5. For a realistic BC-access playthrough, record the documented Business Central page, navigation/search entry, action, FastTab, field values, validations, posting preview, confirmation, generated document numbers, expected G/L, customer, vendor, VAT, bank, item and value entries, drill-down verification, error, correction, and retest. Treat this as structured sandbox simulation, never as evidence that a live BC UI responded.
6. Execute customer and department approvals, UAT sign-off, cutover GO, go-live rehearsal, hypercare acceptance, restart approval, closure, and handover as real gates inside the simulation. Record synthetic roles, inputs, criteria, decisions, exceptions, evidence, and results. These gates can complete the simulation and are not external blockers.
7. Maintain honest states such as `synthetic-complete`, `simulated-complete`, and `synthetisch-abgenommen`. Never claim real execution, production, or customer acceptance. Treat productive use as outside simulation scope, not as an open simulation gate.
8. Use official Microsoft Learn sources where relevant. Record title, URL, retrieval date, related IDs, and a paraphrased conclusion. Separate documented BC behavior, project assumption, synthetic value, and unresolved German localization or tax question.
9. Keep `exports/project-data/v1/index.yaml` as the only current Twin allowlist contract. Include every Twin-visible evidence file in the same normal project commit; do not create an A/B manifest-only commit.
10. Maintain the complete project story: versioned offer and actuals comparison, populated Confluence-style page tree, linked ticket histories, worklogs, evidence, working comments and mandatory closing comments for every done ticket, chronological events from offer through the final hypercare day, and bidirectional references to BC sessions, tests, decisions and deliverables.
11. Deliver one coherent phase commit with relevant tests plus one total check, empty `REVIEW.md`, and a clean worktree. Do not push, merge, tag, or release from the project task.

Completion requires data, all business processes, offer history, Confluence pages, complete ticket lifecycles and closing comments, UAT, training, cutover, go-live rehearsal, every hypercare day, restart, closure, handover, and a readable project timeline to possess concrete synthetic evidence.
