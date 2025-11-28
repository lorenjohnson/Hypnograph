# Hypnograph Architecture Schema

## Mode + App Level Command & HUD Configuration

### 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      HypnographApp                          │
│  - Owns: HypnographState, DreamMode, DivineMode             │
│  - Defines: AppCommands (menu bar commands)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       ContentView                           │
│  - Receives: current mode (HypnographMode protocol)         │
│  - Builds HUD: globalHUDItems() + mode.hudItems()           │
│  - Displays: mode.makeDisplayView()                         │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
            ┌──────────────┐    ┌──────────────┐
            │  DreamMode   │    │  DivineMode  │
            └──────────────┘    └──────────────┘
```

---

## 📋 Command Structure

### **App-Level Commands** (HypnographApp.swift → AppCommands)

These are **global** commands that delegate to the current mode:

| Menu | Command | Key | Delegates To |
|------|---------|-----|--------------|
| **App Menu** | Toggle HUD | `h` | `mode.toggleHUD()` |
| | Pause/Play | `p` | `mode.togglePause()` |
| | Restart Session | `Cmd-R` | `mode.reloadSettings()` |
| **File** | New | `Space` | `mode.new()` |
| | Save | `Cmd-S` | `mode.save()` |
| | Save Snapshot | `s` | `dreamMode.saveSnapshot()` ⚠️ |
| **View** | Cycle Mode | `~` | `cycleMode()` (app-level) |
| | Dream Mode | `Cmd-Shift-1` | `state.currentModeType = .dream` |
| | Divine Mode | `Cmd-Shift-2` | `state.currentModeType = .divine` |
| | Toggle Watch | `w` | `state.toggleWatchMode()` |
| **Composition** | Cycle Global Effect | `e` | `mode.cycleGlobalEffect()` |
| | Add Source | `.` | `mode.addSource()` |
| | Next Source | `→` | `mode.nextSource()` |
| | Previous Source | `←` | `mode.previousSource()` |
| | Select Source 1-9 | `1-9` | `mode.selectSource(index)` |
| | Clear All Effects | `0` | `mode.clearAllEffects()` |
| | **+ Mode-specific** | varies | `mode.compositionCommands()` |
| **Current Source** | Cycle Effect | `f` | `mode.cycleSourceEffect()` |
| | New Random Clip | `n` | `mode.newRandomClip()` |
| | Delete | `Delete` | `mode.deleteCurrentSource()` |
| | Add to Exclude List | `x` | `state.excludeCurrentSource()` |
| | **+ Mode-specific** | varies | `mode.sourceCommands()` |

⚠️ **Issue**: `saveSnapshot()` is Dream-specific but called from app-level commands

---

### **Mode-Specific Commands** (Injected via protocol)

#### **DreamMode.compositionCommands()**
| Command | Key | Action |
|---------|-----|--------|
| Cycle Blend Mode | `m` | `cycleBlendMode()` |
| Toggle Style (Montage/Sequence) | `` ` `` | `toggleStyle()` |

#### **DreamMode.sourceCommands()**
*(empty)*

#### **DivineMode.compositionCommands()**
| Command | Key | Action |
|---------|-----|--------|
| Zoom In | `Cmd-=` | `zoomInStep()` |
| Zoom Out | `Cmd--` | `zoomOutStep()` |
| Reset View | `Cmd-0` | `resetViewTransform()` |

#### **DivineMode.sourceCommands()**
*(empty)*

---

## 🎨 HUD Structure

### **Global HUD Items** (ContentView.globalHUDItems())

| Order | Content | Type |
|-------|---------|------|
| 10 | "Hypnograph" | headline |
| 11 | "Dream Mode" / "Divine Mode" | subheadline |
| 15 | Padding (8pt) | spacer |
| 20 | "Queue: N" | subheadline/caption |
| 25 | Padding (8pt) | spacer |
| 30 | "Global Effect: {name}" | caption |
| 31 | "Source Effect: {name}" | caption |
| 32 | Padding (8pt) | spacer |
| 40 | "H = Toggle HUD" | caption |
| 41 | "P = Pause/Play" | caption |
| 42 | "W = Watch Mode" | caption |
| 43 | Padding (8pt) | spacer |
| 50 | "1-9 = Jump to Source 1-9" | caption |
| 51 | "Space = New random Hypnogram" | caption |
| 52 | "Cmd-S = Save Hypnogram" | caption |
| 53 | "Cmd-R = Reload Settings and Restart" | caption |
| 54 | "Shift-Cmd-S = Show Settings Folder" | caption |

### **DreamMode HUD Items** (DreamMode.hudItems())

| Order | Content | Type |
|-------|---------|------|
| 12 | "Style: Montage/Sequence" | subheadline |
| 25 | "Source {N} of {total}" | caption |
| 41 | "Blend mode (M): {name}" | caption |

### **DivineMode HUD Items** (DivineMode.hudItems())

| Order | Content | Type |
|-------|---------|------|
| 27 | "Space: Clear table" | caption |

---

## 🎮 Controller Mapping

### Layout Philosophy
**Bumpers = Navigation**
**Triggers = Effects (layer-specific)**
**Face buttons = Actions + Global effect**

| Button | Action | Maps To |
|--------|--------|---------|
| **A** (bottom) | New | `mode.new()` |
| **B** (right) | Save (render) | `mode.save()` |
| **X** (left) | **Cycle Global Effect** 🌍 | `mode.cycleGlobalEffect()` |
| **Y** (top) | Snapshot | `dreamMode.saveSnapshot()` |
| **D-Pad ←/→** | Prev/Next Source | `mode.previousSource()` / `nextSource()` |
| **D-Pad ↑** | Add Source | `mode.addSource()` |
| **D-Pad ↓** | Delete Source | `mode.deleteCurrentSource()` |
| **LB** (Left Bumper) | Prev Source | `mode.previousSource()` |
| **RB** (Right Bumper) | Next Source | `mode.nextSource()` |
| **LT** (Left Trigger) | **Cycle Source Effect** 🎨 | `mode.cycleSourceEffect()` |
| **RT** (Right Trigger) | **Cycle Blend Mode** 🎨 | `dreamMode.cycleBlendMode()` |
| **Start/Menu** | Pause/Play | `mode.togglePause()` |
| **Back/Options** | Toggle HUD | `mode.toggleHUD()` |
| **L3** (Left Stick Click) | Toggle Watch | `mode.toggleWatchMode()` |
| **R3** (Right Stick Click) | Cycle Mode | `cycleMode()` |

---

## 🔍 Issues & Observations

### 1. **Snapshot is Dream-specific but called from App-level** ✅ RESOLVED
- `saveSnapshot()` only exists on `DreamMode`
- App commands cast to `DreamMode` to call it
- Controller also casts to `DreamMode` for X button
- **Decision**: Keep Dream-specific, explicit casting is acceptable

### 2. **Blend Mode is Dream-specific** ✅ RESOLVED
- `cycleBlendMode()` is Dream-only (montage style)
- Not exposed in protocol
- Controller casts to `DreamMode` for RB button
- **Decision**: Keep Dream-specific, explicit casting is acceptable

### 3. **Controller mapping complete** ✅ RESOLVED
- **RB** (Right Bumper) → Cycle Blend Mode (prominent!)
- **RT** (Right Trigger) → Cycle Source Effect (layer-specific)
- **LT** (Left Trigger) → Cycle Global Effect (global)
- **X** button → Snapshot

### 4. **HUD order conflicts** ⚠️ STILL EXISTS
- Global uses order 41 for "P = Pause/Play"
- Dream uses order 41 for "Blend mode (M): {name}"
- Both render, but order is ambiguous
- **TODO**: Reserve order ranges to avoid conflicts

---

## 💡 Recommendations

1. **Add to HypnographMode protocol:**
   - `func cycleBlendMode()` (default: no-op, Dream overrides)
   - `func saveSnapshot()` (default: no-op, Dream overrides)

2. **Update controller mapping:**
   - **Prominent blend mode button**: Use **Left Trigger (LT)**
   - **Snapshot button**: Use **Right Trigger (RT)** or **Back/Options**

3. **Fix HUD order conflicts:**
   - Reserve order ranges: 10-19 (header), 20-29 (status), 30-39 (effects), 40-49 (global keys), 50-59 (mode keys)
   - Dream should use 50+ for mode-specific items

4. **Clarify mode-specific vs app-level:**
   - If action only makes sense for one mode, add to protocol with default no-op
   - App-level commands can safely call it on any mode

