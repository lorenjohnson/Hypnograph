# Divine Product Extraction Spec

## Goal
Deliver Divine (tarot-style card table now inside `Hypnograph/Modules/Divine`) as an independent macOS product while keeping Hypnograph's Dream module healthy, reusing shared technology rather than duplicating it.

## Assumptions
- Target platform remains macOS with the current AVFoundation/SwiftUI stack; iOS is out-of-scope for this extraction.
- Both apps continue to read from the same source libraries (folders + Apple Photos via `MediaSourcesLibrary`) unless the user opts into separate libraries later.
- Rendering/export (Renderer/Core, EffectLibrary, AV export) stays owned by Hypnograph initially, but the extraction plan anticipates Divine eventually needing those capabilities.
- Divine cards will keep the existing UX semantics (random clip selection, flip/reveal, drag, zoom) so we can validate parity.
- User data that currently lives under `~/Library/Application Support/Hypnograph` (settings, exclusions, recipes, Quick Look caches) can be migrated/aliased but must not be silently lost.
- We can introduce Swift Package targets or static framework targets to house core code; both Hypnograph and the new Divine app will live in the same Xcode workspace initially.

## Proposed Structure
### Current Module Footprint
- **Divine** (`Hypnograph/Modules/Divine/*.swift`)
  - Depends directly on `HypnographState`, `Settings`, `MediaSourcesLibrary`, `HypnogramSource`/`VideoClip` models, `AppNotifications`, HUD plumbing (`HUDItem`, `HUDView`), gesture utilities, and AVFoundation.
  - Owns UI (`DivineView`), state managers (`DivineCardManager`, `DivinePlayerManager`), and simple audio playback via ad-hoc `AVPlayer` instances.
  - Uses state callbacks (e.g., `state.onWatchTimerFired`) and shared menus defined in `HypnographApp.swift`.
- **Dream** (`Hypnograph/Modules/Dream/*.swift` + `Renderer/`, `EffectLibrary/`, `Audio/`, `Modules/PerformanceDisplay/`)
  - Deeply coupled with renderer pipelines such as `RenderEngine`, `CompositionBuilder`, `FrameCompositor`, and `RenderQueue`.
  - Relies on the effect system (`EffectManager`, `EffectsSession`, metal effect kernels in `Renderer/Effects`), audio routing via `AudioDeviceManager`, and external monitor playback (`LivePlayer`).
  - Shares HUD/menu components and the unified state container.
- **Shared infrastructure**
  - Data + persistence: `HypnographState.swift`, `Settings.swift`, `HypnogramSource.swift`, `HypnogramRecipe.swift`, `RecipeStore.swift`, `HypnogramStore.swift`, `Environment.swift`, `MediaSources/*`, `WindowState.swift`, `WindowRegistration.swift`.
  - UI utilities: `HUDView.swift`, `AppNotifications.swift`, `PhotosPickerSheet.swift`, `EffectsEditorViewModel`, `TooltipManager`, `TextFieldFocusMonitor`.
  - Quick Look target (`HypnogramQuickLook/PreviewViewController.swift`) currently hand-parses `.hypno/.hypnogram` files instead of sharing model types.

### Core Library Extraction Targets
| Library | Responsibilities | Key sources today | Notes |
| --- | --- | --- | --- |
| **HypnoCore** | Settings, recipes, media models, environment paths, exclusion/favorite stores, window state, asset loading/caching/still grabs | `Settings.swift`, `HypnogramState.swift` (split out module-neutral parts), `HypnogramSource.swift`, `HypnogramRecipe.swift`, `RecipeStore.swift`, `HypnogramStore.swift`, `Environment.swift`, `MediaSourcesLibrary.swift`, `ApplePhotos.swift`, `StillImageCache.swift`, `FavoriteStore.swift`, `ExclusionStore.swift`, video thumbnail helpers inside `DivineCardManager`/`Renderer` | Provide mode-agnostic APIs (`LibraryCoordinator`, `WatchTimer`, `WindowStateStore`) so both apps avoid touching Hypnograph-only logic. |
| **HypnoRenderer** | Composition building, frame compositing, export queue, AVPlayer creation, transition helpers | `Renderer/Core/*`, `Renderer/FrameInterpolation`, `Renderer/Effects/*` (metal kernels stay in a Resources bundle), `RenderQueue.swift`, `Modules/PerformanceDisplay/LivePlayer.swift` | Divine does not need export immediately but should compile against the same module so it can add rendering later. |
| **HypnoEffects** | Effect registry/session/editor plumbing shared by Dream preview, Performance display, and future Divine editing | `EffectLibrary/*.swift`, `Renderer/Effects/*.swift`, effect JSON templates under `EffectLibrary` | Keep effect metadata + shader management encapsulated; exposes safe APIs for UI to mutate chains. |
| **HypnoAudio** | Audio routing + monitoring | `Audio/AudioDeviceManager.swift`, audio helpers in `LivePlayer` | Divine currently just plays through default device; factoring this allows future per-card audio output options without reimplementing. |
| **HypnoUI** | Shared SwiftUI components, HUD, AppNotifications, Photos picker sheet, tooltip/text-field utilities, menu wiring | `Views/HUDView.swift`, `Views/AppNotifications.swift`, `Utilities/*.swift`, `Views/PhotosPickerSheet.swift`, `WindowState.swift`, `WindowRegistration.swift` | Expose small composable views plus service objects; Divine app can opt into HUD + notifications without dragging along Dream-only panels. |

### Divine Product Architecture
- **App Target**: new macOS target (e.g., `Divine.app`) that references the extracted packages plus the Divine-specific module.
  - Entry includes a thin `DivineApp` struct mirroring `HypnographApp` but only instantiating `DivineState`, `DivineMode`, and whichever shared managers it needs (render queue optional at first).
  - `DivineState` wraps `HypnoCore` components: maintains active source libraries, exposes `MediaSourcesLibrary`, surfaces `watch` timers, tracks HUD/window visibility, and persists settings to a `~/Library/Application Support/Divine` folder (configurable so advanced users can point both apps at the same store if desired).
  - `DivineCardManager` and `DivineView` stay largely unchanged but consume core services through protocols (`LibraryProviding`, `SnapshotGrabbing`, `NotificationRouting`) to remove direct references to Hypnograph-only singletons.
  - Optional export/render features plug into `HypnoRenderer` later; initial milestone only needs the player/still grabbing subset.
- **Inter-app coordination**
  - Shared packages mean Dream and Divine compile against the same `HypnogramSource`, `EffectChain`, and `MediaFile` representations, enabling recipe import/export between products.
  - Controller/menu inputs (`GameControllerManager`, keyboard shortcuts) move behind `HypnoUI` so the new app does not depend on Hypnograph's `GameControllerManager` unless explicitly enabled.
  - Watching/automation features (Apple Watch timer, `state.onWatchTimerFired`) become part of `HypnoCore.WatchService` to keep Divine's auto-new behavior consistent.

### Quick Look + Supporting Targets
- Refactor `HypnogramQuickLook` to depend on `HypnoCore` instead of manually decoding JSON. This avoids drift when recipe schemas evolve and ensures Divine + Dream generated files preview identically.
- Determine whether Divine spreads will reuse the `.hypno` extension (storing card layout metadata alongside the existing recipe fields) or introduce a `.divine` file. Either way, Quick Look should read shared model types and display card-count/clip summaries accordingly.
- Consider a reusable command-line helper target (today's `Scripts/` + `Add to Hypnograph Sources.workflow`) that both apps can ship for ingesting sources; host it inside a shared `Tools` bundle so we don't ship duplicates.

## Key Decisions
- **Shared package boundaries vs. monolithic target**: adopt Swift Packages for the six libraries above so both apps (and Quick Look/tests) can link only what they need. Static frameworks would also work, but SPM keeps dependency graphs explicit and testable.
- **Data location strategy**: keep a shared default (`~/Library/Application Support/Hypnograph`) but make `Environment.appFolderName` configurable so Divine can default to `~/Library/Application Support/Divine` while still being able to point at Hypnograph's store if the user wants shared recipes.
- **File format compatibility**: prefer extending the existing `.hypno/.hypnogram` recipe format with optional Divine-specific payload (e.g., card positions/orientation) to maximize interoperability and keep Quick Look simple.
- **Testing posture**: build lightweight unit/UI tests around the new packages before relocating code. This ensures each migration step (e.g., moving `MediaSourcesLibrary`) can be validated without spinning up the whole app.
- **Quick Look ownership**: treat Quick Look as a consumer of `HypnoCore` so schema changes only happen in one place, and extend it to optionally render Divine spreads (even if just metadata) to avoid shipping a second extension.

## Open Questions
- Should Divine continue to share the exact same settings + source libraries as Dream by default, or should it fork its own configuration folder to keep card pulls independent?
- Is Divine expected to export renders/video, or is it strictly a live experience? This affects how aggressively we prioritize moving `HypnoRenderer` over.
- Do we need interoperability with Hypnograph's performance display/LivePlayer (e.g., sending a Divine spread to the external monitor), or is Divine strictly single-window?
- What file extension/format should Divine spreads adopt so users can distinguish them from Dream hypnograms in Finder?
- Are there branding/licensing constraints that require separate bundle identifiers, signing profiles, or installer flows for Divine?

## Next Actions (Staged Implementation Plan)
1. **Stage 0 – Baseline capture & guardrails**  
   - Document Divine's current UX flows (screen recordings, menu mappings) and add smoke tests around `DivineCardManager` (e.g., deterministic card creation via a stub `MediaSourcesLibrary`).  
   - Add unit tests for `HypnogramRecipe`, `MediaSourcesLibrary.randomClip`, and Quick Look JSON parsing so we can detect regressions while moving code.  
   - *Verification*: CI job running the new tests plus manual smoke test of Dream + Divine in the shipping Hypnograph app.
2. **Stage 1 – Extract HypnoCore**  
   - Create a Swift Package containing settings, recipe models, environment helpers, media source loaders, and asset caching/still grab helpers. Provide a thin API (`HypnoCoreContext`) that exposes library toggling and watch timers without referencing SwiftUI.  
   - Update Dream + Divine to import the package and remove duplicated logic (e.g., `MediaSourcesLibrary` instantiation from `HypnographState`).  
   - *Verification*: Unit tests for the package plus runtime validation that both modules still load libraries and respond to watch mode toggles.
3. **Stage 2 – Extract HypnoRenderer, HypnoEffects, HypnoAudio**  
   - Move `Renderer/Core/*`, `Renderer/Effects/*`, `EffectLibrary/*`, `Audio/AudioDeviceManager.swift`, and `Modules/PerformanceDisplay/LivePlayer.swift` into dedicated packages.  
   - Introduce façade types (`RenderPipeline`, `EffectsService`, `AudioRouting`) to minimize direct file access. Divine keeps referencing these through protocols even if it only needs still-grab helpers today.  
   - *Verification*: Run existing render/export flows, confirm Hypnogram exports still succeed, and add focused tests for `RenderEngine.makePlayerItem` and `EffectManager`.
4. **Stage 3 – Extract HypnoUI & utilities**  
   - Relocate HUD, AppNotifications, tooltip/text-field helpers, Photos picker, and window-state logic into a Swift Package that produces composable SwiftUI views/services.  
   - Ensure both Dream and Divine adopt the package, allowing the new app to reuse HUD toggles, notifications, and Photos selection without referencing Hypnograph-specific state.  
   - *Verification*: Manual UI test toggling HUD/Photos picker in Hypnograph and (if available) a rudimentary Divine test harness target.
5. **Stage 4 – Stand up Divine.app target**  
   - Create a new macOS app target with its own bundle identifier and `DivineApp` entry point. Wire it to the shared packages plus the existing Divine module files (moved under `DivineApp/Sources` if desired).  
   - Introduce `DivineState` that wraps `HypnoCore` services, re-implement menus/shortcuts locally, and ensure Divine no longer references Hypnograph-only constructs (e.g., GameControllerManager).  
   - *Verification*: Build+run the new app, confirm you can open libraries, add cards, zoom/pan, and that Hypnograph.app still functions.
6. **Stage 5 – Quick Look & packaging alignment**  
   - Point `HypnogramQuickLook` at the shared packages so it can parse both Dream hypnograms and Divine spreads. If a `.divine` extension is introduced, register it here.  
   - Update installer assets/scripts so both apps share optional helpers (CLI, Automator workflows) without duplication.  
   - *Verification*: Quick Look previews still work for `.hypno` files and, if applicable, new `.divine` documents; both app bundles code-sign and notarize cleanly.
7. **Stage 6 – Cleanup & optional renderer enablement**  
   - Once Divine is stable, remove Divine-specific UI/menus from Hypnograph (or keep them behind a build flag) and decide whether Divine should optionally link `HypnoRenderer` for export features.  
   - *Verification*: Regression pass on Hypnograph (Dream only) and final smoke test on Divine with whichever optional renderer features are enabled.

Each stage is independently shippable and testable; we can pause after any step if risk or schedule demands.
