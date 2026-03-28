---
doc-status: done
---

# Sources Window

## Overview

This project added a dedicated `Sources` Studio panel so source-pool management is no longer buried in menu commands.

The new panel lives in the same AppKit window world established by [sidebar-windowization](./20260328-sidebar-windowization/index.md). It exposes media-type filtering, folder-library add/remove/enable/disable, Apple Photos scopes, and a couple of adjacent quick actions for composition file import and custom Photos selection.

One important model correction landed with the UI: folder sources are now added as distinct libraries instead of being silently appended into one `default` bucket. That makes the window's enable/disable and remove behavior truthful rather than cosmetic.

## Notes

- Implemented as a dedicated `Sources` panel in the Studio window host.
- Folder libraries can now be added, removed, and toggled independently.
- `Images` and `Videos` filtering remains available and visible in the panel.
- Apple Photos scopes are manageable from the same surface, including custom selection editing.
- File import is represented as a quick action into composition, not as a persistent source-library type.
- The old `Sources` command menu remains as fallback, but the panel is now the primary surface.

## Review Notes

Questions worth a quick human pass:
- Should the `Sources` panel get its own keyboard shortcut, or is a menu toggle enough for now?
- Do we want to retire more of the old `Sources` command menu now that the panel exists?
- Is `Add File to Composition…` the right adjacent quick action here, or should the panel stay stricter about only showing source-pool controls?
