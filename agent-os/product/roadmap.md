# Roadmap

## Known Issues (Bugs)

- [ ] **Effect name editing broken** - Opens edit mode but can't type. `isTyping` focus disconnect.
- [ ] **Sequence mode saving** - Fails silently or incorrectly.
- [ ] **Output height/width ignored** - Settings file values not applied.
- [ ] **Finder action not installing** - Automator action fails.
- [ ] **Exclude current source** - Unclear if working in Divine mode.

## Near Term

### UX
- [ ] Change `.hypnogram` extension to `.hypno`
- [ ] Click composition source to open in Photos/reveal in Finder
- [ ] Combine HUD into Player Settings modal
- [ ] Default storage to `~/Documents/Hypnograph`
- [ ] Restore window state including clean screen

### Effects Manager
- [ ] Fix effect name editing
- [ ] Copy to Library button in editor
- [ ] Merge from Library button for Favorites

### Player
- [ ] Loop true/false in Player Settings
- [ ] Favorites as playlist manager
- [ ] Basic Sources Window / timeline editor

## Medium Term

### Divine Mode
- [ ] Source library switching (rendered vs normal)
- [ ] Card rotation (Cmd-Arrow)
- [ ] Long press release stops video
- [ ] Cmd-0 zoom to fit
- [ ] Enable/disable card backs
- [ ] Save card layouts with view state

### Montage Mode
- [ ] CMD-# toggles layer blend mode
- [ ] Global reset to Screen blend
- [ ] Auto blend mode sensing

### Performance
- [ ] Stress testing
- [ ] Fix still image in Live View
- [ ] Optimize still image montages

## Long Term

### External Integration
- [ ] Mic input, MIDI Clock, OSC

### Game Controller
- [ ] Scope to essentials only

### Performance Display
- [ ] Configurable transitions (beyond crossfade)

### Distribution
- [ ] QuickLook for .hypno files
- [ ] Divine as separate iOS product

## TestFlight

- [ ] Collect testers, sort paths, finalize icon
- [ ] Apple Developer signup, App Store Connect, TestFlight release

## Tech Debt

### Code Quality
- [ ] **AnyView → @ViewBuilder** - `makeDisplayView()` loses type info
- [ ] **Split Dream.swift** - 1,148 lines, too many responsibilities
- [ ] **Logger migration** - `print()` → `os.log` for levels/filtering
- [ ] **Reduce singletons** - `AudioDeviceManager`, `FavoriteStore`, `ApplePhotos`
- [ ] **Standardize state patterns** - Mixed callbacks/Combine/direct mutation

### Documentation
- [ ] Effects library handling
- [ ] TextFieldFocusMonitor keyboard handling
- [ ] Render library architecture
- [ ] Favorites save/retrieval system

