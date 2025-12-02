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
@MainActor
final class GameControllerManager {

    // Weak references to avoid retain cycles
    private weak var state: HypnographState?
    private weak var dream: Dream?
    private weak var divine: Divine?
    private var cycleModuleHandler: (() -> Void)?

    private var connectedController: GCController?

    init(
        state: HypnographState,
        dream: Dream,
        divine: Divine,
        cycleModule: @escaping () -> Void
    ) {
        self.state = state
        self.dream = dream
        self.divine = divine
        self.cycleModuleHandler = cycleModule

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
    
    // MARK: - Button Handlers

    private func setupButtonHandlers(_ gamepad: GCExtendedGamepad) {
        // A Button (bottom) - New composition (Space)
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }
            switch self.state?.currentModuleType {
            case .dream: self.dream?.new()
            case .divine: self.divine?.new()
            case .none: break
            }
        }

        // B Button (right) - Save (Cmd+S)
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }
            switch self.state?.currentModuleType {
            case .dream: self.dream?.save()
            case .divine: self.divine?.save()
            case .none: break
            }
        }

        // X Button (left) - Cycle global effect (E)
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.cycleGlobalEffect()
        }

        // Y Button (top) - Snapshot (S)
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.saveSnapshot()
        }
    }

    private func setupDPadHandlers(_ gamepad: GCExtendedGamepad) {
        // D-Pad Left - Previous source
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }
            switch self.state?.currentModuleType {
            case .dream: self.dream?.previousSource()
            case .divine: self.divine?.previousCard()
            case .none: break
            }
        }

        // D-Pad Right - Next source
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }
            switch self.state?.currentModuleType {
            case .dream: self.dream?.nextSource()
            case .divine: self.divine?.nextCard()
            case .none: break
            }
        }

        // D-Pad Up - Add source (.)
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }
            switch self.state?.currentModuleType {
            case .dream: self.dream?.addSource()
            case .divine: self.divine?.addCard()
            case .none: break
            }
        }

        // D-Pad Down - Delete source (Delete)
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }
            switch self.state?.currentModuleType {
            case .dream: self.dream?.deleteCurrentSource()
            case .divine: self.divine?.deleteCurrentCard()
            case .none: break
            }
        }
    }

    private func setupBumperHandlers(_ gamepad: GCExtendedGamepad) {
        // Left Bumper - Cycle blend mode (M) for current layer
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.cycleBlendMode()
        }

        // Right Bumper - Cycle source effect (F) for current layer
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.cycleSourceEffect()
        }

        // Left Trigger - Clear all effects and reset blend modes
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.clearAllEffects()
        }

        // Right Trigger - Toggle mode (Montage/Sequence) - Dream only
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.toggleMode()
        }
    }

    private func setupSpecialButtonHandlers(_ gamepad: GCExtendedGamepad) {
        // Start/Menu Button - Pause/Play (P)
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.state?.togglePause()
        }

        // Back/Options Button - Toggle HUD (H) (if available)
        if let optionsButton = gamepad.buttonOptions {
            optionsButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.state?.toggleHUD()
            }
        }

        // Left Stick Click - Toggle watch mode (W) (if available)
        if let leftThumbButton = gamepad.leftThumbstickButton {
            leftThumbButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.state?.toggleWatchMode()
            }
        }

        // Right Stick Click - Cycle module (~) (if available)
        if let rightThumbButton = gamepad.rightThumbstickButton {
            rightThumbButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.cycleModuleHandler?()
            }
        }
    }
}

