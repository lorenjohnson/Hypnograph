# Unified Player Architecture: Implementation Planning

**Created**: 2026-01-16
**Updated**: 2026-01-21
**Status**: Completed (Superseded by Metal Playback Pipeline)

This plan was executed for the AVPlayerView-based unified player work, but the codebase has since moved to the Metal Playback Pipeline (Direction A). This document remains as historical implementation notes.

- See: `archive/20260117-metal-playback-pipeline/overview.md`

This plan details the code-level implementation for unifying Preview and Live player infrastructure.

## Phase 1: Extract ABPlayerCoordinator from LivePlayer

**Goal**: Create a reusable coordinator that manages two AVPlayers and handles transitions.

### New file: `Hypnograph/Dream/ABPlayerCoordinator.swift`

```swift
/// Coordinates two AVPlayer instances for smooth A/B transitions.
/// Handles player lifecycle, transition animation, and active player tracking.
@MainActor
final class ABPlayerCoordinator: NSObject {

    enum Slot { case a, b }

    // MARK: - Players

    private(set) var playerA: AVPlayer
    private(set) var playerB: AVPlayer
    private(set) var activeSlot: Slot = .a

    var activePlayer: AVPlayer {
        activeSlot == .a ? playerA : playerB
    }

    var inactivePlayer: AVPlayer {
        activeSlot == .a ? playerB : playerA
    }

    // MARK: - Views (optional, coordinator can work view-less)

    /// If views are provided, coordinator animates their alpha during transitions
    var playerViewA: AVPlayerView?
    var playerViewB: AVPlayerView?

    var activePlayerView: AVPlayerView? {
        activeSlot == .a ? playerViewA : playerViewB
    }

    var inactivePlayerView: AVPlayerView? {
        activeSlot == .a ? playerViewB : playerViewA
    }

    // MARK: - State

    private(set) var isTransitioning: Bool = false
    private var transitionID: UUID?

    // MARK: - Init

    override init() {
        self.playerA = AVPlayer()
        self.playerB = AVPlayer()
        super.init()
    }

    // MARK: - Transition API

    /// Load a new player item into the inactive player and transition to it.
    /// - Parameters:
    ///   - item: The AVPlayerItem to transition to
    ///   - style: Transition style (none, crossfade, punk)
    ///   - duration: Transition duration in seconds
    ///   - playRate: Playback rate for the new item
    ///   - volume: Volume for the new player
    ///   - audioDeviceUID: Audio output device (nil = system default)
    ///   - isStillImage: If true, seek to zero and pause instead of playing
    ///   - onWillTransition: Called before transition begins
    ///   - onDidTransition: Called after transition completes
    func transition(
        to item: AVPlayerItem,
        style: TransitionStyle,
        duration: TimeInterval,
        playRate: Float,
        volume: Float,
        audioDeviceUID: String?,
        isStillImage: Bool,
        onWillTransition: (() -> Void)? = nil,
        onDidTransition: (() -> Void)? = nil
    ) {
        // Generate unique ID to guard against overlapping transitions
        let thisTransitionID = UUID()
        transitionID = thisTransitionID
        isTransitioning = true

        // Prepare inactive player
        let nextPlayer = inactivePlayer
        let nextView = inactivePlayerView
        let currentView = activePlayerView

        nextPlayer.replaceCurrentItem(with: item)
        nextPlayer.volume = volume
        nextPlayer.audioOutputDeviceUniqueID = audioDeviceUID
        item.audioTimePitchAlgorithm = .timeDomain

        // Mute outgoing player immediately (audio hard cut for now)
        activePlayer.volume = 0

        // Prepare view state
        nextView?.alphaValue = 0

        // Fire willTransition
        onWillTransition?()

        // Start playback on new player
        if isStillImage {
            nextPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            nextPlayer.pause()
        } else {
            nextPlayer.playImmediately(atRate: playRate)
        }

        // Animate transition
        let animate: () -> Void
        let complete: () -> Void

        switch style {
        case .none:
            animate = {
                nextView?.alphaValue = 1
                currentView?.alphaValue = 0
            }
            complete = { [weak self] in
                self?.finalizeTransition(
                    thisTransitionID: thisTransitionID,
                    onDidTransition: onDidTransition
                )
            }
            // Immediate, no animation
            animate()
            complete()
            return

        case .crossfade:
            animate = {
                nextView?.animator().alphaValue = 1
                currentView?.animator().alphaValue = 0
            }

        case .punk:
            // Punk: jittery/stepped alpha progression
            // For now, use crossfade with different timing;
            // Phase 4 will add keyframe animation
            animate = {
                nextView?.animator().alphaValue = 1
                currentView?.animator().alphaValue = 0
            }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animate()
        } completionHandler: { [weak self] in
            self?.finalizeTransition(
                thisTransitionID: thisTransitionID,
                onDidTransition: onDidTransition
            )
        }
    }

    private func finalizeTransition(
        thisTransitionID: UUID,
        onDidTransition: (() -> Void)?
    ) {
        // Guard against stale completion handlers
        guard transitionID == thisTransitionID else { return }

        // Stop and clear old player
        let oldPlayer = activePlayer
        oldPlayer.pause()
        oldPlayer.replaceCurrentItem(with: nil)

        // Swap active slot
        activeSlot = (activeSlot == .a) ? .b : .a
        isTransitioning = false

        onDidTransition?()
    }

    // MARK: - Playback Control (forwards to active player)

    func play(rate: Float) {
        activePlayer.playImmediately(atRate: rate)
    }

    func pause() {
        activePlayer.pause()
    }

    func seek(to time: CMTime) {
        activePlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setVolume(_ volume: Float) {
        activePlayer.volume = volume
    }

    func setAudioDevice(_ deviceUID: String?) {
        playerA.audioOutputDeviceUniqueID = deviceUID
        playerB.audioOutputDeviceUniqueID = deviceUID
    }

    // MARK: - Cleanup

    func tearDown() {
        playerA.pause()
        playerA.replaceCurrentItem(with: nil)
        playerB.pause()
        playerB.replaceCurrentItem(with: nil)
    }
}

/// Transition style for hypnogram changes
enum TransitionStyle: String, Codable, CaseIterable {
    case none
    case crossfade
    case punk

    var displayName: String {
        switch self {
        case .none: return "None"
        case .crossfade: return "Crossfade"
        case .punk: return "Punk"
        }
    }
}
```

### Refactor LivePlayer to use ABPlayerCoordinator

Modify `LivePlayer.swift` to use the new coordinator internally:

**Before** (owns two AVPlayerViews directly):
```swift
private var activePlayer: PlayerSlot = .a
// ... manual A/B logic in performCrossfade
```

**After** (delegates to coordinator):
```swift
private let coordinator = ABPlayerCoordinator()

// In show():
coordinator.playerViewA = content.playerA
coordinator.playerViewB = content.playerB

// In performCrossfade → performTransition:
coordinator.transition(
    to: playerItem,
    style: .crossfade,  // TODO: from settings
    duration: crossfadeDuration,
    playRate: currentClip?.playRate ?? 0.8,
    volume: currentVolume,
    audioDeviceUID: currentAudioDeviceUID,
    isStillImage: isAllStillImages,
    onDidTransition: { [weak self] in
        print("✅ LivePlayer: Transition complete")
    }
)
```

### Acceptance criteria for Phase 1
- [ ] ABPlayerCoordinator extracted and compiles
- [ ] LivePlayer refactored to use coordinator
- [ ] Live transitions work exactly as before (no behavior change)
- [ ] Overlapping transition protection works (transitionID check)

---

## Phase 2: Create HypnogramPlayer

**Goal**: Build the shared player class that both Preview and Live will use.

### New file: `Hypnograph/Dream/HypnogramPlayer.swift`

```swift
/// Shared player for hypnogram playback with A/B transitions.
/// Used by both Preview (via PreviewPlayerView) and Live (via LivePlayer).
@MainActor
final class HypnogramPlayer: ObservableObject {

    // MARK: - Configuration

    var transitionStyle: TransitionStyle = .crossfade
    var transitionDuration: TimeInterval = 0.3

    // MARK: - State

    @Published private(set) var isTransitioning: Bool = false
    @Published var isPaused: Bool = false

    private(set) var currentClip: HypnogramClip?

    var playRate: Float {
        currentClip?.playRate ?? 1.0
    }

    // MARK: - Audio

    var volume: Float = 1.0 {
        didSet { coordinator.setVolume(volume) }
    }

    var audioDeviceUID: String? {
        didSet { coordinator.setAudioDevice(audioDeviceUID) }
    }

    // MARK: - Callbacks

    var onTimeUpdate: ((CMTime) -> Void)?
    var onClipEnded: (() -> Void)?
    var onWillTransition: ((HypnogramClip?, HypnogramClip) -> Void)?
    var onDidTransition: ((HypnogramClip) -> Void)?

    // MARK: - Internal

    let coordinator = ABPlayerCoordinator()
    private let renderEngine = RenderEngine()
    private var pendingLoadTask: Task<Void, Never>?
    private var endObserver: Any?
    private var timeObserver: Any?

    // Configuration for rendering
    var outputSize: CGSize = CGSize(width: 1920, height: 1080)
    var sourceFraming: SourceFraming = .fill
    var effectManager: EffectManager?

    // MARK: - Public API

    /// The currently active AVPlayer (for external observer attachment)
    var activePlayer: AVPlayer {
        coordinator.activePlayer
    }

    /// Load and transition to a new clip
    func load(clip: HypnogramClip) {
        pendingLoadTask?.cancel()

        let previousClip = currentClip
        currentClip = clip

        pendingLoadTask = Task {
            await buildAndTransition(from: previousClip, to: clip)
        }
    }

    private func buildAndTransition(from previousClip: HypnogramClip?, to clip: HypnogramClip) async {
        let config = RenderEngine.Config(
            outputSize: outputSize,
            frameRate: 30,
            enableEffects: true,
            sourceFraming: sourceFraming
        )

        let result = await renderEngine.makePlayerItem(
            clip: clip,
            config: config,
            effectManager: effectManager
        )

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let playerItem):
            let isAllStill = clip.sources.allSatisfy { $0.clip.file.mediaKind == .image }

            // Remove old observers before transition
            removeObservers()

            isTransitioning = true

            coordinator.transition(
                to: playerItem,
                style: transitionStyle,
                duration: transitionDuration,
                playRate: isPaused ? 0 : clip.playRate,
                volume: volume,
                audioDeviceUID: audioDeviceUID,
                isStillImage: isAllStill,
                onWillTransition: { [weak self] in
                    self?.onWillTransition?(previousClip, clip)
                },
                onDidTransition: { [weak self] in
                    guard let self = self else { return }
                    self.isTransitioning = false
                    self.setupObservers(for: playerItem, isStillImage: isAllStill)
                    self.onDidTransition?(clip)
                }
            )

        case .failure(let error):
            print("🔴 HypnogramPlayer: Build failed - \(error)")
        }
    }

    // MARK: - Playback Control

    func play() {
        isPaused = false
        coordinator.play(rate: playRate)
    }

    func pause() {
        isPaused = true
        coordinator.pause()
    }

    func togglePause() {
        if isPaused { play() } else { pause() }
    }

    func seek(to time: CMTime) {
        coordinator.seek(to: time)
    }

    /// Force redraw (for effects changes while paused)
    func forceRedraw() {
        let time = coordinator.activePlayer.currentTime()
        coordinator.seek(to: time)
    }

    // MARK: - Observers

    private func setupObservers(for item: AVPlayerItem, isStillImage: Bool) {
        let player = coordinator.activePlayer

        // Time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.onTimeUpdate?(time)
        }

        // End observer (for looping or watch mode)
        if !isStillImage {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                if let onEnded = self.onClipEnded {
                    onEnded()
                } else {
                    // Default: loop
                    self.coordinator.seek(to: .zero)
                    if !self.isPaused {
                        self.coordinator.play(rate: self.playRate)
                    }
                }
            }
        }
    }

    private func removeObservers() {
        if let token = timeObserver {
            coordinator.activePlayer.removeTimeObserver(token)
            timeObserver = nil
        }
        if let token = endObserver {
            NotificationCenter.default.removeObserver(token)
            endObserver = nil
        }
    }

    // MARK: - Cleanup

    func tearDown() {
        pendingLoadTask?.cancel()
        removeObservers()
        coordinator.tearDown()
        currentClip = nil
    }
}
```

### Acceptance criteria for Phase 2
- [ ] HypnogramPlayer compiles and provides full playback API
- [ ] Callbacks for time, clip end, and transition boundaries work
- [ ] Observer management handles transitions correctly

---

## Phase 3: Migrate LivePlayer to use HypnogramPlayer

**Goal**: LivePlayer becomes a thin wrapper around HypnogramPlayer.

### Changes to LivePlayer.swift

```swift
@MainActor
final class LivePlayer: ObservableObject {

    // MARK: - Configuration (unchanged)
    @Published var config: PlayerConfiguration
    private var sourceFraming: SourceFraming

    // MARK: - Shared player (NEW)
    private let hypnogramPlayer = HypnogramPlayer()

    // MARK: - State (delegate to hypnogramPlayer where possible)
    @Published private(set) var isVisible: Bool = false

    var isTransitioning: Bool { hypnogramPlayer.isTransitioning }
    var hasContent: Bool { hypnogramPlayer.currentClip != nil }
    var activeAVPlayer: AVPlayer? { hypnogramPlayer.activePlayer }

    // ... window management code stays the same ...

    // MARK: - Audio (delegate)
    func setVolume(_ volume: Float) {
        hypnogramPlayer.volume = volume
    }

    func setAudioDevice(_ deviceUID: String?) {
        hypnogramPlayer.audioDeviceUID = deviceUID
    }

    // MARK: - Send (uses HypnogramPlayer)
    func send(clip: HypnogramClip, config: PlayerConfiguration) {
        ensureContentView()

        self.config = config
        self.currentClip = clip

        // Configure player
        hypnogramPlayer.outputSize = renderSize(...)
        hypnogramPlayer.sourceFraming = sourceFraming
        hypnogramPlayer.effectManager = effectManager
        hypnogramPlayer.transitionStyle = .crossfade  // TODO: from settings
        hypnogramPlayer.transitionDuration = crossfadeDuration

        // Wire up views
        if let content = contentView {
            hypnogramPlayer.coordinator.playerViewA = content.playerA
            hypnogramPlayer.coordinator.playerViewB = content.playerB
        }

        // Load clip (triggers transition)
        hypnogramPlayer.load(clip: clip)
    }
}
```

### Acceptance criteria for Phase 3
- [ ] LivePlayer uses HypnogramPlayer internally
- [ ] All existing Live functionality works (window, audio routing, effects)
- [ ] Transition behavior unchanged

---

## Phase 4: Migrate MontagePlayerView to PreviewPlayerView

**Goal**: Rename and refactor to use HypnogramPlayer.

### Rename file
`MontagePlayerView.swift` → `PreviewPlayerView.swift`

### Changes to PreviewPlayerView

The Coordinator now holds a `HypnogramPlayer` instead of managing AVPlayer directly:

```swift
struct PreviewPlayerView: NSViewRepresentable {
    let clip: HypnogramClip
    // ... other properties unchanged ...

    class Coordinator {
        var hypnogramPlayer: HypnogramPlayer?
        var containerView: NSView?
        var playerViewA: AVPlayerView?
        var playerViewB: AVPlayerView?
        var stillClipTimer: Timer?
        var compositionID: String?
        // Remove: player, playerView, timeObserverToken, endObserverToken, etc.
        // These are now managed by HypnogramPlayer
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        context.coordinator.containerView = container

        // Create two player views for A/B
        let viewA = AVPlayerView()
        viewA.controlsStyle = .none
        viewA.translatesAutoresizingMaskIntoConstraints = false

        let viewB = AVPlayerView()
        viewB.controlsStyle = .none
        viewB.translatesAutoresizingMaskIntoConstraints = false
        viewB.alphaValue = 0

        container.addSubview(viewA)
        container.addSubview(viewB)

        // Constraints for both views (fill container)
        for view in [viewA, viewB] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        }

        context.coordinator.playerViewA = viewA
        context.coordinator.playerViewB = viewB

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator

        // Create or configure HypnogramPlayer
        if c.hypnogramPlayer == nil {
            let player = HypnogramPlayer()
            player.coordinator.playerViewA = c.playerViewA
            player.coordinator.playerViewB = c.playerViewB
            c.playerViewA?.player = player.coordinator.playerA
            c.playerViewB?.player = player.coordinator.playerB

            // Wire callbacks
            player.onTimeUpdate = { [weak self] time in
                if self?.currentSourceTime != time {
                    self?.currentSourceTime = time
                }
            }

            player.onClipEnded = { [weak self] in
                guard let self = self else { return }
                if self.watchMode, let onEnded = self.onClipEnded {
                    onEnded()
                }
                // Otherwise HypnogramPlayer loops automatically
            }

            c.hypnogramPlayer = player
        }

        guard let player = c.hypnogramPlayer else { return }

        // Update configuration
        player.outputSize = renderSize(aspectRatio: aspectRatio, maxDimension: displayResolution.maxDimension)
        player.sourceFraming = sourceFraming
        player.effectManager = effectManager
        player.volume = volume
        player.audioDeviceUID = audioDeviceUID
        player.transitionStyle = .crossfade  // TODO: from settings
        player.transitionDuration = 0.3      // TODO: from settings

        // Check if clip changed
        let newID = compositionIdentity(for: clip)
        if newID != c.compositionID {
            c.compositionID = newID
            player.load(clip: clip)
        }

        // Handle pause state
        if isPaused != player.isPaused {
            if isPaused { player.pause() } else { player.play() }
        }

        // Handle effects redraw
        if c.lastEffectsCounter != effectsChangeCounter {
            c.lastEffectsCounter = effectsChangeCounter
            if isPaused {
                player.forceRedraw()
            }
        }

        // Still-clip timer for watch mode (handled separately from HypnogramPlayer)
        // ... existing timer logic ...
    }
}
```

### Update references
- `Dream.swift`: Update `makeDisplayView()` to use `PreviewPlayerView`
- Any other files referencing `MontagePlayerView`

### Acceptance criteria for Phase 4
- [ ] MontagePlayerView renamed to PreviewPlayerView
- [ ] PreviewPlayerView uses HypnogramPlayer internally
- [ ] All existing functionality preserved:
  - [ ] Time binding updates
  - [ ] Pause/play works
  - [ ] Effects redraw while paused
  - [ ] Watch mode auto-advance
  - [ ] Still-image clip handling
  - [ ] Volume and audio device routing
- [ ] Transitions now work in Preview

---

## Phase 5: Add Transition Settings

**Goal**: User-configurable transition style and duration.

### Add to Settings

```swift
// In Settings.swift
var transitionStyle: TransitionStyle = .crossfade
var transitionDuration: TimeInterval = 0.3  // seconds

// Preview and Live can share or have separate settings
var previewTransitionStyle: TransitionStyle = .crossfade
var previewTransitionDuration: TimeInterval = 0.3
var liveTransitionStyle: TransitionStyle = .crossfade
var liveTransitionDuration: TimeInterval = 1.5
```

### Add UI in PlayerSettingsView

```swift
// Transition section
Section("Transitions") {
    Picker("Style", selection: $settings.transitionStyle) {
        ForEach(TransitionStyle.allCases, id: \.self) { style in
            Text(style.displayName).tag(style)
        }
    }

    HStack {
        Text("Duration")
        Slider(value: $settings.transitionDuration, in: 0.1...2.0)
        Text(String(format: "%.1fs", settings.transitionDuration))
    }
}
```

### Wire settings into players

Both `PreviewPlayerView` and `LivePlayer` read from settings when configuring their `HypnogramPlayer`.

### Acceptance criteria for Phase 5
- [ ] Transition settings in Settings model
- [ ] UI for style and duration in PlayerSettingsView
- [ ] Preview respects settings
- [ ] Live respects settings
- [ ] Settings persist

---

## Phase 6: Implement Punk Transition Style

**Goal**: Add the jittery/stepped "punk" transition aesthetic.

### Modify ABPlayerCoordinator

Replace the placeholder punk animation with actual keyframe animation:

```swift
case .punk:
    // Punk: stepped/jittery alpha progression
    performPunkTransition(
        from: currentView,
        to: nextView,
        duration: duration
    ) { [weak self] in
        self?.finalizeTransition(...)
    }
    return
```

```swift
private func performPunkTransition(
    from currentView: AVPlayerView?,
    to nextView: AVPlayerView?,
    duration: TimeInterval,
    completion: @escaping () -> Void
) {
    // Create stepped alpha values with some randomness
    let steps = 8
    let stepDuration = duration / Double(steps)

    var nextAlphas: [CGFloat] = []
    var currentAlphas: [CGFloat] = []

    for i in 0..<steps {
        let progress = Double(i + 1) / Double(steps)
        // Add jitter: ±0.15 random variation
        let jitter = CGFloat.random(in: -0.15...0.15)
        let nextAlpha = min(1.0, max(0.0, CGFloat(progress) + jitter))
        let currentAlpha = min(1.0, max(0.0, CGFloat(1.0 - progress) + jitter))
        nextAlphas.append(nextAlpha)
        currentAlphas.append(currentAlpha)
    }

    // Ensure final state is clean
    nextAlphas[steps - 1] = 1.0
    currentAlphas[steps - 1] = 0.0

    // Animate through steps
    func animateStep(_ index: Int) {
        guard index < steps else {
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = stepDuration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            nextView?.animator().alphaValue = nextAlphas[index]
            currentView?.animator().alphaValue = currentAlphas[index]
        } completionHandler: {
            animateStep(index + 1)
        }
    }

    animateStep(0)
}
```

### Acceptance criteria for Phase 6
- [ ] Punk transition has visible stepped/jittery character
- [ ] Final state is always clean (new=1, old=0)
- [ ] Duration is respected
- [ ] No glitches or stuck states

---

## Phase 7: Boundary Hooks for Volume Leveling

**Goal**: Provide stable integration points for the volume leveling project.

### HypnogramPlayer callbacks are already in place

```swift
var onWillTransition: ((HypnogramClip?, HypnogramClip) -> Void)?
var onDidTransition: ((HypnogramClip) -> Void)?
```

### Integration pattern for volume leveling

```swift
// In Dream or wherever volume leveling is wired:
hypnogramPlayer.onWillTransition = { [weak self] fromClip, toClip in
    guard let self = self, self.settings.volumeLevelingEnabled else { return }

    // Start fade-out of current audio
    // Prepare gain for incoming clip
    self.volumeLeveler.prepareTransition(from: fromClip, to: toClip)
}

hypnogramPlayer.onDidTransition = { [weak self] clip in
    guard let self = self, self.settings.volumeLevelingEnabled else { return }

    // Apply final gain
    // Complete any audio ramps
    self.volumeLeveler.completeTransition(to: clip)
}
```

### Acceptance criteria for Phase 7
- [ ] Boundary hooks fire reliably on every transition
- [ ] Hooks include both old and new clip references
- [ ] Volume leveling project can integrate without modifying player code

---

## Validation Checklist (Full Project)

### Preview functionality preserved
- [ ] Composition builds and plays
- [ ] Time binding updates smoothly
- [ ] Pause/play toggles work
- [ ] Seek works (scrubbing)
- [ ] Effects changes trigger redraw when paused
- [ ] Watch mode auto-advances at clip end
- [ ] Still-image clips display and auto-advance correctly
- [ ] Volume control works
- [ ] Audio device routing works
- [ ] Aspect ratio modes work
- [ ] Source framing (fill/fit) works

### Live functionality preserved
- [ ] Window management (show/hide/fullscreen)
- [ ] External monitor detection and preference
- [ ] Independent effect manager
- [ ] Audio routing to separate device
- [ ] Volume control
- [ ] Transitions work

### New functionality works
- [ ] Transitions work in Preview (previously hard cut)
- [ ] Transition style setting respected
- [ ] Transition duration setting respected
- [ ] Punk style is visually distinct
- [ ] Boundary hooks fire correctly
- [ ] No black frames during transitions
- [ ] Rapid clip navigation doesn't cause glitches
- [ ] Memory usage acceptable (two players)

### Code quality
- [ ] No duplicate transition logic
- [ ] Clear separation: HypnogramPlayer (shared) vs wrappers (specific)
- [ ] Naming is consistent (PreviewPlayerView, not MontagePlayerView)
