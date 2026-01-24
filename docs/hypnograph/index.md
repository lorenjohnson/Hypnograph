# Hypnograph

Hypnograph is a macOS app for creating layered video montages from your photo/video library.

## Structure

```text
hypnograph/
├── projects/           # active projects
│   └── backlog/        # planned, not started
├── archive/            # completed projects
├── architecture/       # system design docs
├── product/            # mission, tech stack, practices
├── reference/          # user-facing docs (controls)
├── roadmap.md          # open loops and tasks
└── index.md            # this file
```

## Directories

**projects/** — Active development work. Each project is a folder or file (`project-name/` or `project-name.md`). `backlog/` holds planned-but-not-started work.

**archive/** — Completed projects, date-prefixed with completion date (`YYYYMMDD-project-name/`). See `archive/index.md` for a log of completed roadmap items.

**architecture/** — System design documentation (effects, rendering, settings, etc.).

**product/** — Product-level docs: mission, tech stack, coding practices.

**reference/** — User-facing reference material (keyboard controls, behaviors).

## Root Files

**roadmap.md** — Open loops, bugs, minor projects, and major project summaries. The "what's next" view.

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

- [Divine docs](../divine/index.md) — The other app in this repo
- [Shared ontology](../shared/ontology/) — Generated domain diagrams
