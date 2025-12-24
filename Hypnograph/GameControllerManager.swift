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
/// - **D-Pad Up/Down** - Navigate effects list or parameters (when Effects Editor is open)
/// - **D-Pad Left/Right** - Adjust parameter values (when Effects Editor is open), or Previous/Next source
/// - **Left Stick X** - Switch between effects and parameters panels (when Effects Editor is open)
/// - **LB** (Left Bumper) - Cycle blend mode (M) - current layer
/// - **RB** (Right Bumper) - Cycle source effect backward (F) - current layer
/// - **LT** (Left Trigger) - Clear all effects and reset blend modes
/// - **RT** (Right Trigger) - Toggle style (Montage/Sequence) - Dream mode
/// - **Start/Menu** - Pause/Play (P)
/// - **Back/Options** - Toggle HUD (H)
/// - **Left Stick Click** - Toggle watch mode (W)
/// - **Right Stick Click** - Send to Performance Display (Cmd+Return)
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
        setupLeftThumbstickHandlers(gamepad)
    }

    /// Check if the effects editor is currently visible
    private var isEffectsEditorVisible: Bool {
        state?.isEffectsEditorVisible ?? false
    }

    /// Get the effects editor view model
    private var effectsViewModel: EffectsEditorViewModel? {
        state?.effectsEditorViewModel
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

        // X Button (left) - Cycle effect (E) for current layer
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.cycleEffect()
        }

        // Y Button (top) - Snapshot (S)
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.saveSnapshot()
        }
    }

    private func setupDPadHandlers(_ gamepad: GCExtendedGamepad) {
        // D-Pad Left - Previous source (parameter adjustment uses native SwiftUI focus)
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }

            if self.isEffectsEditorVisible {
                // In effects editor: left/right handled by native SwiftUI slider focus
                return
            }
            // Normal mode: previous source
            switch self.state?.currentModuleType {
            case .dream: self.dream?.previousSource()
            case .divine: self.divine?.previousCard()
            case .none: break
            }
        }

        // D-Pad Right - Next source (parameter adjustment uses native SwiftUI focus)
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }

            if self.isEffectsEditorVisible {
                // In effects editor: left/right handled by native SwiftUI slider focus
                return
            }
            // Normal mode: next source
            switch self.state?.currentModuleType {
            case .dream: self.dream?.nextSource()
            case .divine: self.divine?.nextCard()
            case .none: break
            }
        }

        // D-Pad Up - Navigate up in effects/parameters
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }

            if self.isEffectsEditorVisible {
                self.navigateEffectsEditor(delta: -1)
            } else {
                // Normal mode: add source
                switch self.state?.currentModuleType {
                case .dream: self.dream?.addSource()
                case .divine: self.divine?.addCard()
                case .none: break
                }
            }
        }

        // D-Pad Down - Navigate down in effects/parameters
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self = self else { return }

            if self.isEffectsEditorVisible {
                self.navigateEffectsEditor(delta: 1)
            } else {
                // Normal mode: delete source
                switch self.state?.currentModuleType {
                case .dream: self.dream?.deleteCurrentSource()
                case .divine: self.divine?.deleteCurrentCard()
                case .none: break
                }
            }
        }
    }

    /// Navigate up/down in the effects editor (effect list only)
    /// Parameter navigation is handled by native SwiftUI focus
    private func navigateEffectsEditor(delta: Int) {
        guard let vm = effectsViewModel, let state = state else { return }

        let globalEffectName = state.renderHooks.globalEffectName

        switch vm.activeSection {
        case .effectList:
            // Move effect selection up/down
            let defs = vm.effectDefinitions
            let currentIndex = vm.selectedEffectIndex(for: globalEffectName)  // -1 = None
            let newIndex = currentIndex + delta

            if newIndex < -1 || newIndex >= defs.count {
                return  // Out of bounds
            }

            if newIndex == -1 {
                state.renderHooks.setGlobalEffect(nil)
            } else if newIndex >= 0 && newIndex < EffectChainLibrary.all.count {
                state.renderHooks.setGlobalEffect(EffectChainLibrary.all[newIndex])
            }

        default:
            // Parameters and text fields use native SwiftUI focus
            break
        }
    }

    private func setupBumperHandlers(_ gamepad: GCExtendedGamepad) {
        // Left Bumper - Cycle blend mode (M) for current layer
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.cycleBlendMode()
        }

        // Right Bumper - Cycle effect backward for current layer
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.dream?.cycleEffect(direction: -1)
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

        // Right Stick Click - Send to Performance Display (Cmd+Return) (if available)
        if let rightThumbButton = gamepad.rightThumbstickButton {
            rightThumbButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.sendToPerformanceDisplay()
            }
        }
    }

    // MARK: - Performance Display

    private func sendToPerformanceDisplay() {
        guard let state = state else { return }

        // Only works when performance display is visible
        guard state.performanceDisplay.isVisible else {
            print("🎮 Performance Display not visible, ignoring send")
            return
        }

        switch state.currentModuleType {
        case .dream:
            guard let dream = dream else { return }
            state.performanceDisplay.send(
                recipe: dream.currentRecipe,
                aspectRatio: state.aspectRatio,
                resolution: state.outputResolution,
                mode: dream.mode
            )
            print("🎮 Sent to Performance Display")
        case .divine:
            print("🎮 Performance Display: Divine mode not supported yet")
        }
    }

    // MARK: - Left Thumbstick for Panel Switching

    private func setupLeftThumbstickHandlers(_ gamepad: GCExtendedGamepad) {
        // Left stick X-axis - Switch between effects and parameters panels
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, _ in
            guard let self = self else { return }

            // Only handle when effects editor is open
            guard self.isEffectsEditorVisible, let vm = self.effectsViewModel else { return }

            // Use a dead zone and threshold to avoid drift and accidental switches
            let threshold: Float = 0.5

            if xValue < -threshold && !self.joystickPanelSwitchTriggered {
                // Joystick pushed left - switch to effects panel
                vm.activeSection = .effectList
                self.joystickPanelSwitchTriggered = true
            } else if xValue > threshold && !self.joystickPanelSwitchTriggered {
                // Joystick pushed right - switch to parameters panel (if effect selected)
                if vm.selectedDefinition(for: self.state?.renderHooks.globalEffectName) != nil {
                    vm.activeSection = .parameterList
                }
                self.joystickPanelSwitchTriggered = true
            } else if abs(xValue) < 0.2 {
                // Joystick returned to center - reset trigger
                self.joystickPanelSwitchTriggered = false
            }
        }
    }

    /// Tracks whether a panel switch has been triggered (prevents repeated switching)
    private var joystickPanelSwitchTriggered = false
}

