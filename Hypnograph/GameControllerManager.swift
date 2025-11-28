import Foundation
import GameController

/// Manages Xbox/PlayStation/MFi game controller input and maps it to app actions.
/// Designed for gallery installations and instrument-like control.
///
/// **Button Mapping:**
/// - **A** (bottom) - New composition (Space)
/// - **B** (right) - Save (Cmd+S)
/// - **X** (left) - Cycle global effect (E)
/// - **Y** (top) - Snapshot (S)
/// - **D-Pad Left/Right** - Previous/Next source (Arrow keys)
/// - **D-Pad Up** - Add source (.)
/// - **D-Pad Down** - Delete source (Delete)
/// - **LB** (Left Bumper) - Cycle blend mode (M) - current layer
/// - **RB** (Right Bumper) - Cycle source effect (F) - current layer
/// - **RT** (Right Trigger) - Toggle style (Montage/Sequence) - Dream mode
/// - **Start/Menu** - Pause/Play (P)
/// - **Back/Options** - Toggle HUD (H)
/// - **Left Stick Click** - Toggle watch mode (W)
/// - **Right Stick Click** - Cycle mode (~)
///
/// Automatically detects and connects to controllers when they're paired via Bluetooth.
final class GameControllerManager {
    
    // Weak references to avoid retain cycles
    private weak var state: HypnographState?
    private weak var dreamMode: DreamMode?
    private weak var divineMode: DivineMode?
    private var cycleModeHandler: (() -> Void)?
    
    private var connectedController: GCController?
    
    init(
        state: HypnographState,
        dreamMode: DreamMode,
        divineMode: DivineMode,
        cycleMode: @escaping () -> Void
    ) {
        self.state = state
        self.dreamMode = dreamMode
        self.divineMode = divineMode
        self.cycleModeHandler = cycleMode
        
        setupControllerObservers()
        
        // Check if controller is already connected
        if let controller = GCController.controllers().first {
            setupController(controller)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Controller Connection
    
    private func setupControllerObservers() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.setupController(controller)
            print("🎮 Game controller connected: \(controller.vendorName ?? "Unknown")")
        }
        
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            if self?.connectedController == controller {
                self?.connectedController = nil
                print("🎮 Game controller disconnected")
            }
        }
    }
    
    private func setupController(_ controller: GCController) {
        connectedController = controller
        
        // Xbox/PlayStation controllers have extendedGamepad profile
        guard let gamepad = controller.extendedGamepad else {
            print("⚠️ Controller doesn't support extended gamepad profile")
            return
        }
        
        setupButtonHandlers(gamepad)
        setupDPadHandlers(gamepad)
        setupBumperHandlers(gamepad)
        setupSpecialButtonHandlers(gamepad)
    }
    
    // MARK: - Current Mode Helper
    
    private var currentMode: (any HypnographMode)? {
        guard let state = state else { return nil }
        switch state.currentModeType {
        case .dream:
            return dreamMode
        case .divine:
            return divineMode
        }
    }
    
    // MARK: - Button Handlers
    
    private func setupButtonHandlers(_ gamepad: GCExtendedGamepad) {
        // A Button (bottom) - New composition (Space)
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.new()
        }

        // B Button (right) - Save (Cmd+S)
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.save()
        }

        // X Button (left) - Cycle global effect (E)
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.cycleGlobalEffect()
        }

        // Y Button (top) - Snapshot (S)
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            // Snapshot is Dream-specific, cast to DreamMode
            if let dreamMode = self?.dreamMode {
                dreamMode.saveSnapshot()
            }
        }
    }
    
    private func setupDPadHandlers(_ gamepad: GCExtendedGamepad) {
        // D-Pad Left - Previous source
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.previousSource()
        }
        
        // D-Pad Right - Next source
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.nextSource()
        }
        
        // D-Pad Up - Add source (.)
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.addSource()
        }
        
        // D-Pad Down - Delete source (Delete)
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.deleteCurrentSource()
        }
    }
    
    private func setupBumperHandlers(_ gamepad: GCExtendedGamepad) {
        // Left Bumper - Cycle blend mode (M) for current layer
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            // Blend mode is Dream-specific, cast to DreamMode
            if let dreamMode = self?.dreamMode {
                dreamMode.cycleBlendMode()
            }
        }

        // Right Bumper - Cycle source effect (F) for current layer
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.cycleSourceEffect()
        }

        // Left Trigger - Clear all effects and reset blend modes
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.clearAllEffects()
        }

        // Right Trigger - Toggle style (Montage/Sequence) - Dream mode only
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dreamMode?.toggleStyle()
        }
    }

    private func setupSpecialButtonHandlers(_ gamepad: GCExtendedGamepad) {
        // Start/Menu Button - Pause/Play (P)
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.currentMode?.togglePause()
        }

        // Back/Options Button - Toggle HUD (H) (if available)
        if let optionsButton = gamepad.buttonOptions {
            optionsButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.currentMode?.toggleHUD()
            }
        }

        // Left Stick Click - Toggle watch mode (W) (if available)
        if let leftThumbButton = gamepad.leftThumbstickButton {
            leftThumbButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.currentMode?.toggleWatchMode()
            }
        }

        // Right Stick Click - Cycle mode (~) (if available)
        if let rightThumbButton = gamepad.rightThumbstickButton {
            rightThumbButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.cycleModeHandler?()
            }
        }
    }
}

