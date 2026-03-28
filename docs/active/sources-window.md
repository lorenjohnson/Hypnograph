---
doc-status: ready
---

# Sources Window

## Overview

Create a dedicated `Sources Window` to replace the current command-menu-heavy source workflow.

The goal is to make source configuration and session source management directly visible and usable, rather than buried in menu actions. The current menu-driven source workflow is not very workable for iterative composition, and source setup is important enough to deserve a first-class surface.

This project should probably happen after [sidebar-windowization](../active/sidebar-windowization/index.md) is settled, since it likely wants to live in the same general AppKit-window world rather than inherit older UI assumptions.

## Rules

- MUST provide a dedicated AppKit source-management window.
- MUST support session source list/table operations (add/remove/enable/disable).
- MUST support source-type filtering (photos/videos/both).
- MUST support source origin controls (folders/files/Photos scopes).
- SHOULD keep this project sequenced after [sidebar-windowization](../active/sidebar-windowization/index.md) stabilizes.

## Plan

Start with one clear window focused on source eligibility for random clip generation. It should make it easy to see what is currently in or out of the source pool and reduce reliance on command-menu actions for the core source-management loop.

The first pass should define the window structure and its entry points, implement a session source list or table with the core operations, add source-origin controls for folders, files, and Photos scopes, and then add media-type filtering. Once that exists, validate persistence behavior and error handling.

The intended outcome is a production-usable `Sources Window` that replaces the current command-menu source workflow with a direct, inspectable, editable source-management surface. The main questions to settle during implementation are whether it should ship as one tabbed window or split later, how Photos scopes should be represented clearly, whether source presets belong in v1, and what belongs to global settings versus per-session state.
