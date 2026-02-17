# Hypnograph docs (structure + rules)

Use this folder for Hypnograph-only documentation.

Structure:
- `roadmap.md` — authoritative current work list
- `projects/` — active project write-ups
- `projects/backlog/` — planned projects not started
- `archive/` — completed project write-ups
- `architecture/` — architecture and system-design notes
- `product/` — product direction and development practices
- `reference/` — user/operator references
- `user-testing/` — test session notes and findings

Workflow:
- current work belongs in `roadmap.md`
- backlog work belongs in `projects/backlog/`
- active work belongs in `projects/`
- completed work moves to `archive/` and is renamed `YYYYMMDD-project-name.md`
- completed roadmap items without project docs go into `archive/done.md` (no date in filename; use dated headings inside)

Project write-ups:
- use a single `.md` file unless the project needs multiple artifacts
- for multi-file projects, use `projects/my-project/index.md` as entrypoint
- link projects from `roadmap.md`

Naming:
- use kebab-case for file/folder names
- use date-prefixed filenames in `archive/`
