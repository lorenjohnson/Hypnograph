---
last_reviewed: 2026-01-04T21:50:51Z
---

# Divine Product Extraction Spec

## Goal
Deliver Divine (tarot-style card table now inside `Hypnograph/Modules/Divine`) as an independent macOS product while keeping Hypnograph's Dream module healthy, reusing shared technology rather than duplicating it.

## Assumptions
- Target platform remains macOS with the current AVFoundation/SwiftUI stack; iOS is out-of-scope for this extraction.
- Divine uses its own app support location and source libraries by default.
- Rendering/export (Renderer/Core, EffectLibrary, AV export) stays owned by Hypnograph initially, but the extraction plan anticipates Divine eventually needing those capabilities.
- Divine cards will keep the existing UX semantics (random clip selection, flip/reveal, drag, zoom) so we can validate parity.
- Divine does not support watch mode; no auto-cycle behavior is required.
- User data that currently lives under `~/Library/Application Support/Hypnograph` (settings, exclusions, recipes) can be migrated/aliased but must not be silently lost.
- We can introduce Swift Package targets or static framework targets to house core code; both Hypnograph and the new Divine app will live in the same Xcode workspace initially.

## Proposed Structure

### Current Module Footprint
- **Divine** (`Hypnograph/Modules/Divine/*.swift`)
  - Depends directly on `HypnographState`, `Settings`, `MediaLibrary`, `HypnogramSource`/`VideoClip` models, `AppNotifications`, HUD plumbing (`HUDItem`, `HUDView`), gesture utilities, and AVFoundation.
  - Owns UI (`DivineView`), state managers (`DivineCardManager`, `DivinePlayerManager`), and simple audio playback via ad-hoc `AVPlayer` instances.
  - Uses state callbacks (e.g., `state.onWatchTimerFired`) and shared menus defined in `HypnographApp.swift`.
- **Dream** (`Hypnograph/Modules/Dream/*.swift` + `Renderer/`, `EffectLibrary/`, `Audio/`, `Modules/LivePlayer/`)
  - Coupled to renderer entry points such as `RenderEngine` and `RenderEngine.ExportQueue`.
  - Relies on the effect system (`EffectManager`, `EffectsSession`, metal effect kernels in `Renderer/Effects`), audio routing via `AudioDeviceManager`, and external monitor playback (`LivePlayer`).
  - Shares HUD/menu components and the unified state container.
- **Shared infrastructure**
  - Data + persistence: `HypnographState.swift`, `Settings.swift`, `HypnogramSource.swift`, `HypnogramRecipe.swift`, `RecipeStore.swift`, `HypnogramStore.swift`, `Environment.swift`, `MediaSources/*`, `WindowState.swift`, `WindowRegistration.swift`.
  - UI utilities: `HUDView.swift`, `AppNotifications.swift`, `PhotosPickerSheet.swift`, `EffectsEditorViewModel`, `TooltipManager`, `TextFieldFocusMonitor`.
    - Note: `PhotosPickerSheet.swift` is deprecated for now and should not be treated as a required shared surface for Divine extraction.

### Core Library Extraction Targets

| Library | Responsibilities | Key sources today | Notes |
| --- | --- | --- | --- |
| **HypnoCore** | Media models, media sourcing, Photos integration, exclusion/favorites stores, shared path config, asset loading/caching/still grabs | `MediaLibrary.swift`, `MediaLibraryBuilder.swift`, `ApplePhotos.swift`, `StillImageCache.swift`, `PersistentIdentifierStore.swift` (ExclusionStore, SourceFavoritesStore), `HypnoCoreConfig.swift`, video thumbnail helpers inside `DivineCardManager`/`Renderer` | Stage 1 keeps this intentionally focused on media + stores; recipes/settings can remain app-owned until needed. |
| **HypnoRenderer** | Composition building, frame compositing, export queue, AVPlayer creation, transition helpers | `Renderer/Core/*`, `Renderer/FrameInterpolation`, `Renderer/Effects/*` (metal kernels stay in a Resources bundle), `RenderEngine.ExportQueue` | LivePlayer stays in the app (AppKit/windowing); Divine does not need export immediately but should compile against the same module so it can add rendering later. |
| **HypnoEffects** | Effect registry/session/editor plumbing shared by Dream preview, Live display, and future Divine editing | `EffectLibrary/*.swift`, `Renderer/Effects/*.swift`, effect JSON templates under `EffectLibrary` | Keep effect metadata + shader management encapsulated; exposes safe APIs for UI to mutate chains. |
| **HypnoAudio** | Audio routing + monitoring | `Audio/AudioDeviceManager.swift`, audio helpers in `LivePlayer` | Divine currently just plays through default device; factoring this allows future per-card audio output options without reimplementing. |
| **HypnoAppShell** (name TBD) | App-agnostic shell services and non-visual utilities shared by multiple products | `Views/AppNotifications.swift`, `Utilities/TextFieldFocusMonitor.swift`, `WindowState.swift` | Keep this intentionally small and non-opinionated about UI. A richer shared `HypnoUI` view library (sliders, panels, HUD variants) can come later once Divine.app exists and shared widgets are proven. |

### Divine Product Architecture
- **App Target**: new macOS target (e.g., `Divine.app`) that references the extracted packages plus the Divine-specific module.
  - Entry includes a thin `DivineApp` struct mirroring `HypnographApp` but only instantiating `DivineState`, `DivineMode`, and whichever shared managers it needs (render queue optional at first).
- `DivineState` wraps `HypnoCore` components: owns its `MediaLibrary`, library selections, and exclusion stores, and persists settings to a `~/Library/Application Support/Divine` folder. No watch mode or HUD/window-state concerns live here.
  - `DivineCardManager` and `DivineView` stay largely unchanged but consume core services through protocols (`LibraryProviding`, `SnapshotGrabbing`, `NotificationRouting`) to remove direct references to Hypnograph-only singletons.
  - Optional export/render features plug into `HypnoRenderer` later; initial milestone only needs the player/still grabbing subset.
- **Inter-app coordination**
  - Shared packages mean Dream and Divine compile against the same `HypnogramSource`, `EffectChain`, and `MediaFile` representations, enabling recipe import/export between products.
  - Keep controller/menu inputs (`GameControllerManager`, keyboard shortcuts) app-owned for now; once Divine.app exists we can decide whether any input abstractions belong in a shared shell layer.
  - Watching/automation features (Apple Watch timer, `state.onWatchTimerFired`) become part of `HypnoCore.WatchService` to keep Divine's auto-new behavior consistent.

### Supporting Targets
- Consider a reusable command-line helper target (today's `Scripts/` + `Add to Hypnograph Sources.workflow`) that both apps can ship for ingesting sources; host it inside a shared `Tools` bundle so we don't ship duplicates.

## Key Decisions
- **Frameworks now, SwiftPM later (optional)**: keep Xcode framework targets in the shared workspace for the initial extraction; revisit SwiftPM only if it meaningfully improves reuse/build ergonomics (Stage 6).
- **Data location strategy**: Divine defaults to `~/Library/Application Support/Divine`.
- **File format compatibility**: keep Divine's future spread format flexible; avoid committing to a storage format until Divine.app behavior stabilizes.
- **Testing posture**: build lightweight unit/UI tests around the new packages before relocating code. This ensures each migration step (e.g., moving `MediaLibrary`) can be validated without spinning up the whole app.

## Open Questions
- Is Divine expected to export renders/video, or is it strictly a live experience? This affects how aggressively we prioritize moving `HypnoRenderer` over.
- Do we need interoperability with Hypnograph's Live display (e.g., sending a Divine spread to the external monitor), or is Divine strictly single-window?
- What file extension/format should Divine spreads adopt so users can distinguish them from Dream hypnograms in Finder?
- Are there branding/licensing constraints that require separate bundle identifiers, signing profiles, or installer flows for Divine?

---

## Staged Implementation Plan

### Stage 0 – Baseline capture & guardrails
**Status: Complete**
- [x] Add a minimal, deterministic `DivineCardManager` test (stubbed library, verifies card creation + uniqueness).
- [x] Add unit tests for `HypnogramRecipe`, `MediaLibrary.randomClip`, and hypnogram JSON parsing so we can detect regressions while moving code.
- [x] Remove unused `RenderQueue` wiring from `Divine` and its initialization in `HypnographApp`.
- [x] Introduce a minimal `DivineState` class (no protocols yet) and update `Divine`/`DivineCardManager` to use it instead of `HypnographState` directly.
- [x] Restore a minimal Divine HUD (module name + shortcut hints) and remove Divine no-op stubs (`toggleHUD`, `togglePause`).

### Stage 1 – Extract HypnoCore
**Status: Complete**
- Create a `HypnoCore` framework target at the repo root focused on media sourcing.
- Move media sourcing + cache + store files into `HypnoCore`: `MediaLibrary`, `ApplePhotos`, `StillImageCache`, `PersistentIdentifierStore`.
- Extract `MediaKind`, `MediaFile`, `VideoClip`, `CodableCMTime`, and `CodableCGAffineTransform` into `HypnoCore`.
- Introduce `HypnoCoreConfig` for shared paths.
- Update Dream + Divine to import `HypnoCore`.

### Stage 2 – Extract HypnoRenderer, HypnoEffects, HypnoAudio
**Status: Complete**
- Move `Renderer/Core/*`, `Renderer/Effects/*`, `EffectLibrary/*`, and `Audio/AudioDeviceManager.swift` into dedicated frameworks.
- Ensure new frameworks depend on `HypnoCore` for shared media models.
- Update renderer/effects resource loading to use framework bundles.

### Stage 2.5.1 – HypnoRenderer API cleanup
**Status: Complete**
- Move UI-only helpers back into the app: `MetalImageView`, `ImageUtils`, and `FrameProcessor`.
- Hide pipeline internals and route app usage through `RenderEngine` only.
- Replace `RenderQueue`/`HypnogramRenderer` with `RenderEngine.ExportQueue`.

### Stage 2.8 – Parameterize core stores
**Status: Complete**
- Replace `SourceFavoritesStore.shared` and `ExclusionStore.shared` with explicit instances owned by app state.
- Avoid disk IO at singleton init time.

### Stage 3 – Extract HypnoAppShell
- Extract **AppNotifications** into a small shared framework.
- Extract **WindowState** as a pure model (Codable).
- Extract **TextFieldFocusMonitor** or equivalent.
- Remove Divine's dependency on the Hypnograph HUD pipeline.

### Stage 4 – Stand up Divine.app target
**Status: Complete**
- Create a new macOS app target with its own bundle identifier and `DivineApp` entry point.
- Introduce a full `DivineState` that owns its settings, library selection, and persistence.
- Re-implement menus/shortcuts locally.

### Stage 5 – Cleanup & optional renderer enablement
**Status: Complete**
- Remove Divine-specific UI/menus from Hypnograph.
- Link `HypnoRenderer` for export features.

### Stage 5.5 – Framework consolidation
**Status: Complete**
- Consolidate HypnoEffects, HypnoRenderer, HypnoAudio into HypnoCore.
- Rename HypnoAppShell to HypnoUI.
- **Goal**: Two frameworks total—HypnoCore (no UI deps) and HypnoUI (SwiftUI/AppKit utilities).

**Target structure for HypnoCore:**
```
HypnoCore/
├── HypnoCoreConfig.swift
├── AudioDeviceManager.swift
├── Media/
├── Renderer/
│   ├── RenderEngine.swift
│   ├── FrameCompositor.swift
│   ├── ExportQueue.swift
│   ├── FrameInterpolation/
│   └── Effects/
├── Recipes/
└── Cache/
```

**Target structure for HypnoUI:**
```
HypnoUI/
├── AppNotifications.swift
├── WindowState.swift
└── TextFieldFocusMonitor.swift
```

**Framework dependencies after consolidation:**
| Framework | Dependencies |
|-----------|--------------|
| HypnoCore | Foundation, Metal, AVFoundation, Photos, CoreMedia |
| HypnoUI   | SwiftUI, AppKit, HypnoCore |

### Stage 6 (Optional) – Packaging audit (frameworks → SPM)
- Evaluate whether staying on Xcode frameworks is "good enough" or whether SwiftPM materially improves day-to-day workflow.
- Criteria: repository boundary, resource model, build ergonomics, Xcode integration.

Each stage is independently shippable and testable; we can pause after any step if risk or schedule demands.
