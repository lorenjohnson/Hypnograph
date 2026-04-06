# Agent Directives

## Normative Status

- This file defines normative routing and system directives for LLM sessions in this project.
- `README.md` is human-facing context and MUST NOT be treated as routing policy.

## Required Load Order

1. shared product-context-manager principles: `../product-context-manager/principles.md`
2. shared product-context-manager rules: `../product-context-manager/rules.md`
3. `docs/rules.md`
4. shared product-context-manager tools: `../product-context-manager/tasks/README.md`
5. shared product-context-manager workflow: `../product-context-manager/workflow.md`
6. shared product-context-manager personality: `../product-context-manager/personality.md`
7. `docs/product.md`
8. `docs/queue.md` and linked project docs as needed

## Rules

- You MUST treat shared product-context-manager guidance as the base system.
- You MUST apply project-local rules after shared guidance.
- You SHOULD load shared `../product-context-manager/project-template.md` only when creating a new project doc via the New Project event in `workflow.md`.
- If `docs/rules.md` conflicts with shared rules, project-local rules MUST win for this project.
- You MUST keep routing/system directives in `AGENTS.md`.
- You MUST keep `README.md` human-centric and non-normative.
