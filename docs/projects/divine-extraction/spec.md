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
  - Depends directly on `HypnographState`, `Settings`, `MediaSourcesLibrary`, `HypnogramSource`/`VideoClip` models, `AppNotifications`, HUD plumbing (`HUDItem`, `HUDView`), gesture utilities, and AVFoundation.
  - Owns UI (`DivineView`), state managers (`DivineCardManager`, `DivinePlayerManager`), and simple audio playback via ad-hoc `AVPlayer` instances.
  - Uses state callbacks (e.g., `state.onWatchTimerFired`) and shared menus defined in `HypnographApp.swift`.
- **Dream** (`Hypnograph/Modules/Dream/*.swift` + `Renderer/`, `EffectLibrary/`, `Audio/`, `Modules/PerformanceDisplay/`)
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
| **HypnoCore** | Media models, media sourcing, Photos integration, exclusion/favorite/deletion stores, shared path config, asset loading/caching/still grabs | `MediaSourcesLibrary.swift`, `ApplePhotos.swift`, `StillImageCache.swift`, `FavoriteStore.swift`, `ExclusionStore.swift`, `DeleteStore.swift`, `HypnoCoreConfig.swift`, video thumbnail helpers inside `DivineCardManager`/`Renderer` | Stage 1 keeps this intentionally focused on media + stores; recipes/settings can remain app-owned until needed. |
| **HypnoRenderer** | Composition building, frame compositing, export queue, AVPlayer creation, transition helpers | `Renderer/Core/*`, `Renderer/FrameInterpolation`, `Renderer/Effects/*` (metal kernels stay in a Resources bundle), `RenderEngine.ExportQueue` | LivePlayer stays in the app (AppKit/windowing); Divine does not need export immediately but should compile against the same module so it can add rendering later. |
| **HypnoEffects** | Effect registry/session/editor plumbing shared by Dream preview, Performance display, and future Divine editing | `EffectLibrary/*.swift`, `Renderer/Effects/*.swift`, effect JSON templates under `EffectLibrary` | Keep effect metadata + shader management encapsulated; exposes safe APIs for UI to mutate chains. |
| **HypnoAudio** | Audio routing + monitoring | `Audio/AudioDeviceManager.swift`, audio helpers in `LivePlayer` | Divine currently just plays through default device; factoring this allows future per-card audio output options without reimplementing. |
| **HypnoAppShell** (name TBD) | App-agnostic shell services and non-visual utilities shared by multiple products | `Views/AppNotifications.swift`, `Utilities/TextFieldFocusMonitor.swift`, `WindowState.swift` | Keep this intentionally small and non-opinionated about UI. A richer shared `HypnoUI` view library (sliders, panels, HUD variants) can come later once Divine.app exists and shared widgets are proven. |

### Divine Product Architecture
- **App Target**: new macOS target (e.g., `Divine.app`) that references the extracted packages plus the Divine-specific module.
  - Entry includes a thin `DivineApp` struct mirroring `HypnographApp` but only instantiating `DivineState`, `DivineMode`, and whichever shared managers it needs (render queue optional at first).
- `DivineState` wraps `HypnoCore` components: owns its `MediaSourcesLibrary`, library selections, and exclusion/favorite stores, and persists settings to a `~/Library/Application Support/Divine` folder. No watch mode or HUD/window-state concerns live here.
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
- **File format compatibility**: keep Divine’s future spread format flexible; avoid committing to a storage format until Divine.app behavior stabilizes.
- **Testing posture**: build lightweight unit/UI tests around the new packages before relocating code. This ensures each migration step (e.g., moving `MediaSourcesLibrary`) can be validated without spinning up the whole app.

## Open Questions
- Is Divine expected to export renders/video, or is it strictly a live experience? This affects how aggressively we prioritize moving `HypnoRenderer` over.
- Do we need interoperability with Hypnograph's performance display/LivePlayer (e.g., sending a Divine spread to the external monitor), or is Divine strictly single-window?
- What file extension/format should Divine spreads adopt so users can distinguish them from Dream hypnograms in Finder?
- Are there branding/licensing constraints that require separate bundle identifiers, signing profiles, or installer flows for Divine?

## Next Actions (Staged Implementation Plan)
1. **Stage 0 – Baseline capture & guardrails**  
   - **Status: Complete**  
   - [x] Add a minimal, deterministic `DivineCardManager` test (stubbed library, verifies card creation + uniqueness).  
   - [x] Add unit tests for `HypnogramRecipe`, `MediaSourcesLibrary.randomClip`, and hypnogram JSON parsing so we can detect regressions while moving code.  
   - [x] Remove unused `RenderQueue` wiring from `Divine` and its initialization in `HypnographApp`.  
   - [x] Introduce a minimal `DivineState` class (no protocols yet) and update `Divine`/`DivineCardManager` to use it instead of `HypnographState` directly. In Stage 0 this can be a thin adapter that delegates to `HypnographState` so behavior stays stable while the dependency surface shrinks.  
   - [x] Restore a minimal Divine HUD (module name + shortcut hints) and remove Divine no-op stubs (`toggleHUD`, `togglePause`).  
   - *Verification*: CI job running the new tests plus manual smoke test of Dream + Divine in the shipping Hypnograph app. (Automated tests passing locally.)
2. **Stage 1 – Extract HypnoCore**  
   - **Status: Complete**  
   - Create a `HypnoCore` framework target at the repo root focused on media sourcing (not the full recipe/settings surface yet).  
   - Move media sourcing + cache + store files into `HypnoCore`: `MediaSourcesLibrary`, `ApplePhotos`, `StillImageCache`, `ExclusionStore`, `DeleteStore`, `FavoriteStore`.  
   - Extract `MediaKind`, `MediaFile`, `VideoClip`, `CodableCMTime`, and `CodableCGAffineTransform` into `HypnoCore` (e.g., `MediaModels.swift`). Keep `HypnogramSource.swift` in the app, updated to import `HypnoCore`.  
   - Move `SourceMediaType` into `HypnoCore`; keep `Settings.swift` in the app but import `HypnoCore` for the enum.  
   - Introduce `HypnoCoreConfig` for shared paths (app support, Photos hidden cache) and initialize it from the app; keep `Environment` inside the Hypnograph app.  
   - Update Dream + Divine to import `HypnoCore` and remove duplicated media library wiring (e.g., `MediaSourcesLibrary` construction, store access).  
   - Keep `HypnoCore`’s public API intentionally small (media models, `MediaSourcesLibrary`, stores, `HypnoCoreConfig`) so it can migrate to SPM without rethinking call sites.  
   - *Verification*: Unit tests for media models + `MediaSourcesLibrary.randomClip`, plus runtime validation that both modules still load libraries and respond to watch mode toggles.
3. **Stage 2 – Extract HypnoRenderer, HypnoEffects, HypnoAudio**  
   - **Status: Complete**  
   - Move `Renderer/Core/*`, `Renderer/Effects/*`, `EffectLibrary/*`, and `Audio/AudioDeviceManager.swift` into dedicated frameworks.  
   - Ensure new frameworks depend on `HypnoCore` for shared media models and Photos access.  
   - Update renderer/effects resource loading to use framework bundles (avoid `Bundle.main` for Metal and effect JSON assets).  
   - Use a single public entry point type per subsystem (RenderEngine, EffectManager, AudioDeviceManager). If we later want stricter public surface control, add thin facades and reduce access in Stage 7. Divine keeps referencing these through protocols even if it only needs still-grab helpers today.  
   - *Verification*: macOS build + focused unit tests covering `RenderEngine.makePlayerItem`, `RenderEngine.makePlayerItemForSource`, still-image export, and `EffectManager` lookback.
4. **Stage 2.5.1 – HypnoRenderer API cleanup**  
   - **Status: Complete**  
   - Move UI-only helpers back into the app: `MetalImageView`, `TransitionManager`, `ImageUtils`, and `FrameProcessor`.  
   - Hide pipeline internals (`CompositionBuilder`, `RenderInstruction`, `FrameCompositor`) and route app usage through `RenderEngine` only.  
   - Replace `RenderQueue`/`HypnogramRenderer` with `RenderEngine.ExportQueue`.  
   - Add `RenderEngine.Timeline` and a single-source player-item API for sequence playback.  
   - *Verification*: macOS build + unit tests for render pipeline entry points; manual playback smoke test pending.
5. **Stage 2.8 – Parameterize core stores (remove singleton + global config ordering hazards)**  
   - Replace `FavoriteStore.shared`, `ExclusionStore.shared`, and `DeleteStore.shared` with explicit instances owned by app state (`HypnographState`, `DivineState`).  
   - Avoid disk IO at singleton init time; store instances should be constructed with explicit URLs/config so they cannot accidentally read/write to the wrong app support directory.  
   - Keep `HypnoCoreConfig` for shared path calculation, but treat it as an input when creating store instances rather than global mutable state that stores implicitly depend on.  
   - *Verification*: Unit tests can point stores at a temporary directory; Hypnograph runtime behavior unchanged.

6. **Stage 3 – Extract HypnoAppShell (notifications + window state + input gating)**  
   - Extract **AppNotifications** into a small shared framework, but remove Hypnograph-specific branding (e.g., inject notification title/app identity from each app target).  
   - Extract **WindowState** as a pure model (Codable) so both apps can share the clean-screen / visibility semantics without sharing specific overlays or panels.  
   - Extract **TextFieldFocusMonitor** (macOS) or an equivalent “is typing” gate so both apps can reliably disable single-key shortcuts while editing text.  
   - Remove Divine’s dependency on the Hypnograph HUD pipeline (`HUDItem` / `hudItems()`); explicitly allow Divine to have *no HUD* until Divine.app’s table UX is designed.  
   - Keep **HUDView** and **TooltipManager** app-owned for now (Hypnograph-only); do not attempt to standardize a shared overlay aesthetic in this stage.  
   - Treat `PhotosPickerSheet.swift` as deprecated/out-of-scope for this extraction; do not pull it into shared frameworks at this stage.  
   - *Verification*: Manual test (Hypnograph) for notifications + clean screen + typing/shortcut gating; no Divine UI parity requirements at this stage.

7. **Stage 4 – Stand up Divine.app target**  
   - Create a new macOS app target with its own bundle identifier and `DivineApp` entry point. Wire it to the shared packages plus the existing Divine module files (moved under `DivineApp/Sources` if desired).  
   - Introduce a full `DivineState` that owns its settings, library selection, and persistence (no `HypnographState` dependency), re-implement menus/shortcuts locally, and ensure Divine no longer references Hypnograph-only constructs (e.g., GameControllerManager).  
   - *Verification*: Build+run the new app, confirm you can open libraries, add cards, zoom/pan, and that Hypnograph.app still functions.
8. **Stage 5 – Cleanup & optional renderer enablement**  
   - Once Divine is stable, remove Divine-specific UI/menus from Hypnograph (or keep them behind a build flag) and decide whether Divine should optionally link `HypnoRenderer` for export features.  
   - *Verification*: Regression pass on Hypnograph (Dream only) and final smoke test on Divine with whichever optional renderer features are enabled.
9. **Stage 6 (Optional) – Packaging audit (frameworks → SPM)**  
   - Evaluate whether staying on Xcode frameworks is “good enough” for the expected ecosystem (Divine + 1–3 sibling apps in the same workspace) or whether SwiftPM materially improves your day-to-day.  
   - Criteria to decide:
     - **Repository boundary**: do you expect these libraries to be reused outside this repo/workspace (or by external contributors/CI tooling)? If yes, SwiftPM is usually worth it.
     - **Resource model**: would moving resource lookups from framework bundles to `Bundle.module` be straightforward for effect JSON/LUT/text assets, and is Metal shader compilation supported in your desired build workflow (Xcode-only vs `swift build`)?
     - **Build ergonomics**: do you need `swift test` / command-line builds to be first-class, or is Xcode-centric development fine?
     - **Xcode integration**: do you rely on framework-specific behaviors (e.g., asset catalogs, build phases, embedding/signing) that are simpler as frameworks?
   - If migration is favorable, plan a staged move that preserves public API shape and build/test parity.  
   - *Verification*: Both apps build cleanly after the packaging decision; no resource lookup regressions.

Each stage is independently shippable and testable; we can pause after any step if risk or schedule demands.
