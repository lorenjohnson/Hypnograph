# Divine Mode Extraction Plan

Note: `spec.md` in this folder is the current source of truth. This plan captures the earlier, lighter-weight extraction outline.

**Date:** 2025-12-26  
**Goal:** Extract Divine Mode into a standalone macOS app using the Hypnograph engine

## Overview

Divine Mode is a tarot-style card viewer that displays media clips as draggable cards on a canvas. Unlike Dream mode (which composites layered video with effects), Divine is relatively simple and self-contained, making it a good candidate for extraction into its own app.

## Current Divine Mode Dependencies

### What Divine Actually Uses from HypnographState

| Access | Where | What It Needs |
|--------|-------|---------------|
| `state.settings.outputDuration.seconds` | DivineCardManager | Just a `Double` for clip length |
| `state.library.randomClip(clipLength:)` | DivineCardManager | Random clip from library |
| `state.library.exclude(file:)` | Divine | Exclude a source |
| `state.isTyping` | Divine | Disable shortcuts while typing |
| `state.noteUserInteraction()` | Divine | Reset watch timer (could be no-op) |
| `state.reloadSettings()` | Divine | Reload and restart |
| `FavoriteStore.shared` | Divine | Toggle favorite (static singleton) |

### What Divine Does NOT Use

- `windowState` (effects editor, sources window, HUD visibility, etc.)
- `effectsEditorViewModel`
- `aspectRatio` / `outputResolution` (rendering settings)
- `performanceDisplay`
- Any recipe/composition system
- Watch timer callbacks
- `RenderQueue` (passed in but never used - `save()` is stubbed)
- Entire `Renderer/` folder (effects, shaders, frame buffer, etc.)

---

## Stage 1: Isolate Divine (Do Now)

**Goal:** Further decouple Divine from Hypnograph internals without breaking anything.  
**Estimated time:** ~45 minutes

### Step 1.1: Remove `renderQueue` from Divine (5 min)

Divine has `let renderQueue: RenderQueue` but `save()` just prints "not supported". Remove this unused dependency.

**Files to modify:**
- `Hypnograph/Modules/Divine/Divine.swift` - Remove renderQueue property and init parameter
- `Hypnograph/HypnographApp.swift` - Update Divine initialization

### Step 1.2: Create `DivineMediaProvider` Protocol (15 min)

Define a minimal protocol for Divine's media needs:

```swift
protocol DivineMediaProvider {
    func randomClip(clipLength: Double) -> VideoClip?
    func exclude(file: MediaFile)
}

protocol DivineConfig {
    var clipDuration: Double { get }
    var isTyping: Bool { get }
    func noteUserInteraction()
}
```

### Step 1.3: Update DivineCardManager to Use Protocol (15 min)

Have `DivineCardManager` depend on the protocol instead of `HypnographState` directly. This makes the extraction boundary explicit.

### Step 1.4: Document the Divine Dependency Boundary (10 min)

Add comments in Divine.swift noting the minimal interface it requires.

---

## Stage 2: Create Shared Module Structure (Future)

**Goal:** Extract shared code into a reusable module that both apps can use.  
**Estimated time:** 4-6 hours

### What Goes in Shared Module (HypnographCore)

| Component | Used By |
|-----------|---------|
| `MediaFile`, `VideoClip` | Both |
| `MediaSourcesLibrary` | Both |
| `ApplePhotos` | Both |
| `StillImageCache` | Both |
| `ExclusionStore`, `FavoriteStore`, `DeleteStore` | Both |
| `SourceMediaType`, `MediaKind` | Both |
| `Environment` (app paths) | Both |
| `Settings` (subset - source folders, media types) | Both |

### Module Options

1. **Swift Package in separate repo** - Cleanest separation, versioned independently
2. **Local Swift Package in same repo** - Easier to manage, shared history
3. **Folder/module within Xcode project** - Simplest start, can upgrade later

---

## Stage 3: Branch and Extract

**Goal:** Create the divine-app branch and clean up main.  
**Estimated time:** 2-3 hours

### Workflow

```
1. Create divine-app branch (freeze point)
         ↓
2. Back on main: Extract shared code into HypnographCore module
         ↓
3. Make Dream/Hypnograph import from HypnographCore
         ↓
4. Remove Divine Mode from main (it was using the same shared code)
         ↓
5. On divine-app branch: Rebuild Divine to import HypnographCore
```

---

## Stage 4: Build Standalone Divine App

**Goal:** Create a minimal app shell for Divine.  
**Estimated time:** 4-6 hours

### Divine App Structure

```
DivineApp/
├── DivineApp.swift           # SwiftUI App entry point
├── DivineState.swift         # Simplified state (replaces HypnographState)
├── Settings.swift            # Stripped down settings
├── Environment.swift         # App paths
└── Divine/                   # Copied from Hypnograph
    ├── Divine.swift
    ├── DivineCard.swift
    ├── DivineCardManager.swift
    ├── DivinePlayerManager.swift
    ├── DivineView.swift
    ├── CanvasScrollHandler.swift
    └── CardBack.png
```

### What Gets Simplified/Removed

- No render pipeline - Divine doesn't export, just plays
- No effects system - No Metal shaders, frame buffer
- No Dream mode - Single-purpose app
- No Performance Display - Single window
- Simplified library - Just "point at Photos album or folder"
- No watch timer - Divine doesn't auto-cycle

---

## Total Estimated Effort

| Phase | Effort |
|-------|--------|
| Stage 1: Isolate Divine | ~45 min |
| Stage 2: Create shared module | 4-6 hours |
| Stage 3: Branch and extract | 2-3 hours |
| Stage 4: Build standalone app | 4-6 hours |
| Testing & polish | 2-3 hours |
| **Total** | **~13-19 hours** |

---

## Future: iOS Adaptation

Deferred until macOS extraction is complete. iOS would additionally require:

- Replace `NSImage`/`NSView` → `UIImage`/`UIView`
- Touch gestures instead of mouse
- `PHPicker` for Photos access
- Simplified single-folder or Photos-only source (iOS sandbox constraints)
- Responsive layout for different screen sizes
