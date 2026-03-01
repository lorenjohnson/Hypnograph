---
created: 2026-03-01
updated: 2026-03-01
status: proposed
---

# Sources Window

## Overview

Create a dedicated `Sources Window` to replace the current command-menu-heavy source workflow.

Goal: make source configuration and session source management directly visible and usable, rather than buried in menu actions.

## Why this project exists

- Current sources menu workflow is not very usable for iterative composition work.
- Source setup is a core operation and needs a first-class surface.
- This scope is intentionally separate from sidebar-to-AppKit windowization.

## Related Projects

- [sidebar-windowization](../active/sidebar-windowization.md)
- [composition-timeline-pivot-spike](./composition-timeline-pivot-spike.md)

## Scope

### In scope

- Dedicated AppKit window for source management.
- Source list/table for session-eligible sources.
- Add/remove/enable/disable source entries.
- Source-type filtering controls (photos/videos/both).
- Source origin controls (folders/files/Photos scopes).

### Out of scope (initial)

- Timeline/NLE data model changes.
- Effects model redesign.
- Full media-library backend rewrite.
- Final UX polish and set/grouping systems.

## UX Direction (initial)

- One clear window focused on source eligibility for random clip generation.
- Fast visibility into what is currently in/out of the source pool.
- Minimize command-menu dependency for core source tasks.

## Proposed First Pass

1. Define window structure and entry points (menu/shortcut/show-hide behavior).
2. Implement session source table/list with core operations.
3. Add source scope controls (file/folder/Photos selection modes).
4. Add media-type filter controls and confirm behavior in random generation.
5. Validate persistence behavior and error handling.

## Open Questions

1. Should this ship as one tabbed window or split into multiple windows later?
2. How should Photos scopes be represented for clarity and speed?
3. Should source favorites/presets be in v1 or deferred?
4. Which data belongs to global settings vs per-session state?

## Deliverable

A production-usable `Sources Window` that replaces the current command-menu-first source workflow with a direct, inspectable, editable source-management surface.
