---
doc-status: done
---

# Custom Metal-Based Blend Modes

**Date:** 2025-12-25

## Overview

Create custom blend modes using Metal shaders that go beyond Core Image's built-in blend modes. These would enable more creative, circuit-bending style compositing between multiple video sources.

This first iteration will be R&D and experimental. We don't need to figure out the UI other than adding any custom blend modes to the list of options we can cycle over with the "m" key for a layer.

## Current State

Blend modes use Core Image's built-in `CIFilter` blend filters:
- `CIScreenBlendMode`, `CIMultiplyBlendMode`, `CIOverlayBlendMode`, etc.
- Limited to CI's predefined set (~15 modes)
- Applied in `ImageUtils.blend()` and `FrameCompositor`

## Goal

Write custom blend mode shaders in Metal for:
- More control over blending math
- Artistic/non-standard modes not available in Core Image
- Better performance by avoiding CIFilter overhead
- Motion-aware or temporal blending

## Architecture Overview

### Components Needed

1. **Metal Shader File** (`CustomBlendShader.metal`)
   - Contains blend kernel functions
   - Each function takes foreground and background samples, returns blended result
   - Must use `CIBlendKernel` compatible signature:
   ```metal
   extern "C" float4 myBlendMode(coreimage::sample_t fg, coreimage::sample_t bg)
   ```

2. **Kernel Registry** (`CustomBlendKernels.swift`)
   - Loads Metal library and creates `CIBlendKernel` instances
   - Caches kernels for reuse
   - Maps mode names to Metal function names

3. **Blend Mode Constants** (`BlendModes.swift`)
   - Add custom modes to the `BlendMode` enum
   - Use "Custom" prefix to distinguish from CI built-ins
   - Add to `BlendMode.all` array for random selection

4. **Routing** (`ImageUtils.swift`)
   - Check if mode is custom (`BlendMode.isCustom()`)
   - Route to `CustomBlendKernels.blend()` instead of `CIFilter`

### Example Blend Mode Implementation

```metal
// In CustomBlendShader.metal

#include <CoreImage/CoreImage.h>
using namespace metal;

// Utility: luminance calculation
inline float luminance(float3 color) {
    return dot(color, float3(0.299, 0.587, 0.114));
}

// Example: Ghostly Add Blend
// Soft additive where brighter foreground adds more
extern "C" float4 ghostlyAddBlend(coreimage::sample_t fg, coreimage::sample_t bg) {
    float fgLuma = luminance(fg.rgb);
    float blendAmt = smoothstep(0.0, 1.0, fgLuma);
    float3 result = bg.rgb + fg.rgb * blendAmt * 0.7;
    return float4(clamp(result, 0.0, 1.0), 1.0);
}
```

### Swift Side Registration

```swift
// In CustomBlendKernels.swift

enum CustomBlendKernels {
    static let prefix = "Custom"

    static let availableModes = ["CustomGhostlyAdd"]

    private static var kernelCache: [String: CIBlendKernel] = [:]

    static func kernel(for mode: String) -> CIBlendKernel? {
        if let cached = kernelCache[mode] { return cached }

        let functionName = metalFunctionName(for: mode)
        let kernel = try? CIBlendKernel(
            functionName: functionName,
            fromMetalLibraryData: getMetalLibraryData()
        )
        kernelCache[mode] = kernel
        return kernel
    }

    static func blend(_ fg: CIImage, over bg: CIImage, mode: String) -> CIImage {
        guard let kernel = kernel(for: mode) else { return fg }
        return kernel.apply(foreground: fg, background: bg) ?? fg
    }

    private static func metalFunctionName(for mode: String) -> String {
        switch mode {
        case "CustomGhostlyAdd": return "ghostlyAddBlend"
        default: return "ghostlyAddBlend"
        }
    }

    private static func getMetalLibraryData() -> Data {
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        return try! Data(contentsOf: url)
    }
}
```

## Potential Custom Modes

| Mode | Description |
|------|-------------|
| Ghostly Add | Soft additive with falloff based on luminance |
| Motion Blend | Blend amount driven by motion detection |
| Gradient Dissolve | Blend based on luminance gradient |
| Chromatic Layer | Different blend per RGB channel |
| Temporal Cross | Blend based on frame history |
| Noise Dissolve | Dithered blend with noise threshold |

## Implementation Approaches

### Option A: CIBlendKernel (Recommended)

```swift
// CustomBlendKernels.swift
import CoreImage

class GhostlyAddKernel: CIBlendKernel {
    static let kernel: CIBlendKernel = {
        let metalCode = """
        #include <CoreImage/CoreImage.h>

        extern "C" float4 ghostlyAdd(coreimage::sample_t fg,
                                      coreimage::sample_t bg) {
            float fgLuma = dot(fg.rgb, float3(0.299, 0.587, 0.114));
            float blendAmt = smoothstep(0.0, 1.0, fgLuma);
            float3 result = bg.rgb + fg.rgb * blendAmt * 0.7;
            return float4(clamp(result, 0.0, 1.0), 1.0);
        }
        """
        return try! CIBlendKernel(functionName: "ghostlyAdd",
                                   fromMetalLibraryData: metalCode.data(using: .utf8)!)
    }()
}
```

### Option B: Full Metal Compute Shader

For complex blends needing more than two inputs (e.g., motion-aware):

```metal
// CustomBlendShader.metal
kernel void motionAwareBlend(
    texture2d<float, access::read> foreground [[texture(0)]],
    texture2d<float, access::read> background [[texture(1)]],
    texture2d<float, access::read> motionField [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float4 fg = foreground.read(gid);
    float4 bg = background.read(gid);
    float2 motion = motionField.read(gid).rg;

    float motionMag = length(motion);
    float blendAmt = smoothstep(0.0, 0.3, motionMag);

    // Screen blend in motion areas, normal elsewhere
    float3 screenBlend = 1.0 - (1.0 - fg.rgb) * (1.0 - bg.rgb);
    float3 result = mix(fg.rgb, screenBlend, blendAmt);

    output.write(float4(result, 1.0), gid);
}
```

## Integration Points

1. **BlendModes.swift** - Add custom mode names to `BlendMode.all`
2. **ImageUtils.blend()** - Detect custom modes, route to Metal kernel
3. **FrameCompositor** - Already calls `ImageUtils.blend()`, no changes needed
4. **UI** - Blend mode picker already cycles through `BlendMode.all`

---

## Metal Optical Flow for Motion Detection

### Current State

Temporal effects detect motion using **frame difference**:
- Simple pixel subtraction: `abs(current - previous)`
- Returns magnitude only (0-1 scalar)
- No direction information
- Used in: DatamoshShader, PixelDriftShader, GlitchBlocksShader, IFrameShader

### Goal

Compute **motion vectors** (direction + magnitude per pixel) using optical flow.

### Benefits

| Feature | Current (Frame Diff) | With Optical Flow |
|---------|---------------------|-------------------|
| Motion magnitude | ✓ | ✓ |
| Motion direction | ✗ | ✓ |
| Smear along motion | Random | Accurate |
| Motion blur | Fake | Realistic |
| Object tracking | ✗ | Possible |

### Implementation Approaches

#### Option A: Vision Framework (Simpler)

```swift
import Vision

class OpticalFlowProcessor {
    private let request = VNGenerateOpticalFlowRequest()

    func computeFlow(from previous: CVPixelBuffer,
                     to current: CVPixelBuffer) -> CVPixelBuffer? {
        let handler = VNImageRequestHandler(cvPixelBuffer: current)
        request.targetedCVPixelBuffer = previous

        try? handler.perform([request])

        // Returns 2-channel float buffer (dx, dy per pixel)
        return request.results?.first?.pixelBuffer
    }
}
```

**Pros:** Apple-optimized, GPU-accelerated, easy to use
**Cons:** iOS 14+/macOS 11+, less control over algorithm

#### Option B: Metal Compute Shader (More Control)

Implement Lucas-Kanade or Horn-Schunck algorithm:

```metal
// OpticalFlowShader.metal
kernel void lucasKanade(
    texture2d<float, access::read> current [[texture(0)]],
    texture2d<float, access::read> previous [[texture(1)]],
    texture2d<float, access::write> flowField [[texture(2)]],
    constant OpticalFlowParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Compute spatial gradients Ix, Iy
    // Compute temporal gradient It
    // Solve for (u, v) motion vector
    // Output: float2(u, v) per pixel
}
```

**Pros:** Full control, can tune for artistic vs accurate
**Cons:** More work, need to implement/tune algorithm

### Integration

1. **New: MotionField class** - Holds motion vector texture
2. **RenderContext** - Add `motionField: MotionField?` property
3. **FrameBuffer** - Compute flow when adding frames, cache result
4. **Effects** - Access `context.motionField` for directional motion

### Effects That Would Benefit

- **DatamoshMetalEffect** - Drift in motion direction, not random
- **PixelDriftMetalEffect** - Smear trails follow actual motion
- **GlitchBlocksMetalEffect** - Streak direction matches motion
- **New: MotionBlurEffect** - Realistic directional blur
- **New: MotionExtrudeEffect** - Extrude pixels along motion path

---

## Priority & Effort

| Feature | Effort | Impact | Priority |
|---------|--------|--------|----------|
| CIBlendKernel custom modes | Low | Medium | 1 |
| Full Metal blend shaders | Medium | Medium | 2 |
| Vision optical flow | Medium | High | 3 |
| Metal optical flow | High | High | 4 |

**Recommended order:** Start with CIBlendKernel for quick wins, then Vision optical flow for biggest visual improvement with moderate effort.

## Why Parked

The implementation was touching multiple files and adding complexity before the core use case (frame interpolation for slow-mo) was complete. Better to:

1. Complete optical flow for frame interpolation first
2. Return to custom blend modes with fresh approach
3. Start with ONE visible, obviously working blend mode as proof of concept
4. Then expand to more exotic modes

## Files That Were Created (Now Reverted)

- `Hypnograph/Renderer/Core/CustomBlendShader.metal` - Metal kernels
- `Hypnograph/Renderer/Core/CustomBlendKernels.swift` - Swift registry
- Modifications to `BlendModes.swift` - Added custom mode constants
- Modifications to `ImageUtils.swift` - Added routing logic
