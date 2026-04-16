# Agent Directives

## Normative Status

- This file defines normative routing and system directives for LLM sessions in this project.

## Required Default Load Order

1. shared product-context-manager principles: `../product-context-manager/principles.md`
2. shared product-context-manager rules: `../product-context-manager/rules.md`
3. `docs/rules.md`
4. shared product-context-manager workflow: `../product-context-manager/workflow.md`
5. `docs/product.md`

## Rules

- You MUST treat shared product-context-manager guidance as the base system.
- You MUST apply project-local rules after shared guidance.
- You MUST load only the default load set plus any additional files explicitly called for by system documents or by the user.
- If `docs/rules.md` conflicts with shared rules, project-local rules MUST win for this project.
- You MUST keep routing/system directives in `AGENTS.md`.
- You MUST keep `README.md` human-centric and non-normative.
