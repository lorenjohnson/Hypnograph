---
doc-status: draft
---

# Nonlinear Timeline Editor

## Overview

Replace the current playbar timeline/sequence strip with a keyboard-first, simplified nonlinear timeline editor. The goal is a cleaner editing instrument than a full NLE: fast clip navigation, ripple edits, trims, slips, effects, and random source insertion without DaVinci-level UI weight.

This document is an early UI/interaction sketch. Keep it concrete and revise by looking at the interface and keymap.

## Keymap / Operations

Design pressure: keep one canonical way to do each operation. Avoid persistent modes except clip selection.

| Key | Mode / Operation | Behavior |
| --- | --- | --- |
| `Space` | Play / Pause | Toggle playback. |
| `Left` / `Right` | Navigate | Focus previous / next clip in timeline order. |
| `Shift+Left` / `Shift+Right` | Move clip | Move selected/focused clip earlier/later in sequence. |
| `Enter` | Toggle clip selection | Select focused clip and enter/continue clip-selection mode; if already selected, deselect it. |
| `Backspace` | Ripple delete focused clip | Delete currently highlighted clip and close the gap. |
| `Option+Left` / `Option+Right` | Trim clip | Shorten / extend focused clip duration. |
| `Option+Shift+Left` / `Option+Shift+Right` | Slip clip | Shift source window inside focused clip duration. |
| `Esc` | Clear / exit selection | Exact behavior TBD: likely clear selection or leave selection mode. |
| `Cmd+Z` | Undo | Undo last timeline edit. |
| `Cmd+Shift+Z` | Redo | Redo last undone timeline edit. |
| `M` | Blend mode | Cycle focused clip blend mode. |
| `Cmd+C` | Copy | Copy focused clip or selected clips. |
| `Cmd+X` | Cut | Cut focused clip or selected clips; whether ripple or leave gap TBD. |
| `Cmd+V` | Paste after | Paste copied/cut clip(s) after focused clip. |
| `N` | New clip after | Create a new clip after the focused clip using a random source by default; if no source is available, prompt for a clip. |
| `Shift+N` | New clip before | Create a new clip before the focused clip using a random source by default; if no source is available, prompt for a clip. |

## Persistent Modes

Modes are persistent states that remain active after keys are released and require an explicit exit.

| Mode | Purpose | Possible Non-Modal Alternative |
| --- | --- | --- |
| Select clips | Build a selection one clip at a time. | `Enter` toggles focused clip in/out of selection. |

## Timeline Mockup

```text
│  00:00        00:05        00:10        00:15        00:20        00:25      │
│  ──┬───────────┬───────────┬───────────┬───────────┬───────────┬──────      │
│    │                                                                        │
│    │ [ clip A ]────[FOCUSED clip B]────[ clip C ]────[ clip D ]────[ clip E ]│
│    │                                                                        │
│    ▲ playhead                                                               │
│ Focus: clip B   Source: 00:02.4-00:07.8   Blend: Screen                      │
│ Space Play/Pause   Enter Select   ⇧←/→ Move   ⌥←/→ Trim   ⌥⇧←/→ Slip   M Mix │
```
