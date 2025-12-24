//
//  RenderHooks.swift
//  Hypnograph
//
//  Created by Loren Johnson on 19.11.25.
//
//  REFACTORED: This file has been split into focused modules:
//
//  Core Rendering:
//    - SharedRenderer.swift: Metal device and CIContext
//    - FrameBuffer.swift: GPU-efficient ring buffer for temporal effects
//    - RenderContext.swift: Per-frame rendering context
//
//  Effects System:
//    - Effect.swift: Effect protocol and extensions
//    - ParameterSpec.swift: Parameter metadata and extraction
//
//  Effect Library:
//    - EffectChainLibrary.swift: Available effect chains
//    - EffectManager.swift: Runtime effect management
//
//  This file is kept for backward compatibility and will be removed
//  after all references are updated.
//

import Foundation

// MARK: - Backward Compatibility Aliases

// These typealiases ensure existing code continues to work during migration.
// They can be removed once all call sites are updated to use the new types directly.

// Note: RenderHookManager typealias is now in EffectManager.swift
 
