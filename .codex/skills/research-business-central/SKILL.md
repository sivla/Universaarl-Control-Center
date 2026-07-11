---
name: research-business-central
description: Research current primary Business Central documentation and map it to BC Basic use cases, configuration decisions, tests, training, cutover, and operations. Use whenever project assumptions or expected BC steps need official support, especially finance, posting groups, VAT, purchasing, sales, payments, reconciliation, inventory, period close, or German localization.
---

# Research Business Central

1. Search current primary sources, preferring Microsoft Learn and official Microsoft documentation. For legal or tax claims, use authoritative German government sources in addition to Microsoft product documentation.
2. Record title, URL, retrieval date, related use-case or decision ID, and a short paraphrased conclusion. Do not copy long passages.
3. Separate four categories explicitly:
   - documented Business Central standard behavior;
   - project-specific assumption;
   - synthetic simulation value;
   - unresolved localization, accounting, or tax question.
4. Map sources directly to setup, P2P, O2C, payment and reconciliation, inventory, month-end, VAT preview, UAT, training, cutover, or operations artifacts. Do not create a second knowledge system.
5. Treat sources as support for expected behavior and acceptance criteria, never as evidence that a BC transaction actually ran.
6. When source and project data conflict, record a defect or open decision; do not silently normalize the project.
7. Keep research read-only and free of customer secrets, authentication state, or live-system access.
