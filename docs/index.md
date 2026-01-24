# Documentation

This repo contains two macOS apps and shared code. Documentation is organized by app context.

## Apps

**[Hypnograph](hypnograph/)** — Layered video montage creator
**[Divine](divine/)** — Photo/video library explorer as dynamic card layout

## Shared

**[shared/](shared/)** — Cross-app documentation and generated artifacts (ontology diagrams, domain models)

## Structure (per app)

Each app follows the same documentation pattern:

```text
<app>/
├── projects/           # project specs (active work)
├── archive/            # completed projects (date-prefixed)
├── roadmap.md          # open loops, bugs, task summaries
└── ...                 # app-specific directories
```

Hypnograph also includes:
- `architecture/` — System design docs (effects, rendering, settings)
- `product/` — Product-level docs (mission, tech stack, practices)
- `reference/` — User-facing reference (keyboard controls)

## Project Lifecycle

```text
roadmap.md  →  projects/  →  archive/
(idea)         (planning)    (done)
```

1. Ideas captured in `roadmap.md`
2. When ready to plan: create doc in `projects/`
3. When complete: move to `archive/` with date prefix (`YYYYMMDD-project-name/`)

## Agents

**[agents/](agents/)** — Canonical agent role definitions for AI-assisted development. Tool-agnostic descriptions used for planning, reasoning, and cross-AI handoff. Claude-specific runtime agents (in `.claude/agents/`) are derived from these.

## Related

- [Shared ontology](shared/ontology/) — Generated domain diagrams
