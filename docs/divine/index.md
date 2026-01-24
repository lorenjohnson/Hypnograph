# Divine

Divine is a macOS app for exploring your photo/video library as a dynamic card layout.

## Structure

```text
divine/
├── projects/           # project specs
├── archive/            # completed projects
├── roadmap.md          # open loops and tasks
└── index.md            # this file
```

## Directories

**projects/** — Development work. Each project is a folder or file (`project-name/` or `project-name.md`).

**archive/** — Completed projects, date-prefixed with completion date (`YYYYMMDD-project-name/`).

## Root Files

**roadmap.md** — Open loops, bugs, minor projects, and major project summaries.

**index.md** — This documentation.

## Project Lifecycle

```text
roadmap.md  →  projects/  →  archive/
(idea)         (planning)    (done)
```

1. Ideas captured in `roadmap.md`
2. When ready to plan: create doc in `projects/`
3. When complete: move to `archive/` with date prefix

## Related

- [Hypnograph docs](../hypnograph/index.md) — The other app in this repo
- [Shared ontology](../shared/ontology/) — Generated domain diagrams
