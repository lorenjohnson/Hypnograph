---
doc-status: ready
---

# In-App Feedback

## Overview

Add a simple feedback mechanism to Hypnograph that gives users an easy way to share bug reports and feature suggestions directly from the app. This is especially important during beta as a communication channel with testers.

## Rules

- MUST provide free-form text input for bug reports, feature suggestions, and general thoughts.
- MUST provide a type selector (`Bug` / `Feedback` / `Idea` or equivalent).
- MUST keep access low-friction and visible during beta.
- MUST route submissions to a reviewable destination.
- SHOULD expose entry via command menu / shortcut.
- SHOULD keep the UI as a small window or sheet.

## Plan

Keep it minimal, but do it thoughtfully. One input box, type selector (bug / feedback / idea), and submit action to a lightweight backend (Airtable/Notion/email?). Include device/version info automatically with submissions.

- [ ] Design the UI (input box, type picker, submit button)
- [ ] Decide on backend (Airtable form? Notion API? mailto?)
- [ ] Build the window/sheet in SwiftUI
- [ ] Add menu item and keyboard shortcut
- [ ] Consider even briefly having a "record voice feedback" option
- [ ] Test submission flow
