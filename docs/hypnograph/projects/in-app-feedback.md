# In-App Feedback

**Status:** Planning
**Created:** 2026-01-24

## Overview

Add a simple feedback mechanism to Hypnograph that gives users an easy way to share bug reports and feature suggestions directly from the app. This is especially important during beta as a communication channel with testers.

## Context

The third-party feedback/roadmap products (Canny, Nolt, etc.) are priced for a scale that doesn't match what we're building. Their economics assume larger audiences and monetized products. But AI-assisted development changes the math — it's now possible to build quality apps for smaller audiences without traditional monetization. These products outscale what we need.

More importantly: building this ourselves aligns with a vision for how this software practice works. The brand being built here is about a certain kind of collaborative workflow with users — one where lower friction to implement feedback means users have more direct impact. The feedback mechanism is part of that relationship, not just a utility.

So: build it, keep it minimal, but do it thoughtfully.

## Decision

**Build a simple in-app feature.** One input box, type selector (bug / feedback / idea), submit button. Backend can be as simple as Airtable, Notion, or even email.

## What This Feature Does

- Free-form text input for bug reports, feature suggestions, general thoughts
- Type selector: Bug / Feedback / Idea (or similar)
- Easy to access, low friction, prominent during beta
- Submissions go somewhere reviewable (Airtable, email, etc.)

## Placement

- **Command menu** — Primary access point (Cmd+?)
- **Prominent during beta** — Not buried
- **Simple window** — Could be a sheet or small modal

## Plan

- [ ] Design the UI (input box, type picker, submit button)
- [ ] Decide on backend (Airtable form? Notion API? mailto?)
- [ ] Build the window/sheet in SwiftUI
- [ ] Add menu item and keyboard shortcut
- [ ] Test submission flow

## Open Questions

- Voice memo input? (nice-to-have, side quest)
- Include device/version info automatically with submissions?
- Where exactly do submissions land? (Airtable is low-friction to set up)
