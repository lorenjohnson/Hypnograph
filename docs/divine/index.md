# Divine

Divine is a macOS app for exploring your photo/video library as a dynamic card layout.

## Structure

```text
divine/
├── projects/           # active projects
│   └── backlog/        # planned, not started
├── archive/            # completed projects
├── roadmap.md          # open loops and tasks
└── index.md            # this file
```

## Directories

**projects/** — Active development work. Each project is a date-prefixed folder or file (`YYYYMMDD-project-name/`). `backlog/` holds planned-but-not-started work.

**archive/** — Completed projects. Same naming convention.

## Root Files

**roadmap.md** — Open loops, bugs, minor projects, and major project summaries.

**index.md** — This documentation.

## Project Lifecycle

```text
roadmap.md  →  projects/backlog/  →  projects/  →  archive/
(idea)         (planned)            (active)      (done)
```

1. Ideas captured in `roadmap.md`
2. When ready to plan: create doc in `projects/backlog/`
3. When starting work: move to `projects/` root
4. When complete: move to `archive/` with date prefix

## Related

- [Hypnograph docs](../hypnograph/index.md) — The other app in this repo
- [Shared ontology](../shared/ontology/) — Generated domain diagrams
