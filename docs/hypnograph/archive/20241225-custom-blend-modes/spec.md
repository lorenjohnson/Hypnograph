# Custom Metal-Based Blend Modes

**Date:** 2025-12-25  
**Status:** Parked - implementation started but reverted for cleaner approach later

## Goal

Create custom blend modes using Metal shaders that go beyond Core Image's built-in blend modes. These would enable more creative, circuit-bending style compositing between multiple video sources.

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

## Blend Mode Ideas (For Future)

1. **Ghostly Add** - Luminance-based additive, brighter areas add more
2. **Gradient Dissolve** - Blend varies by luminance gradient
3. **Chromatic Layer** - Different blend per RGB channel (screen/multiply/overlay)
4. **Noise Dithered** - Organic dithered transitions
5. **Motion Blend** - Uses optical flow to blend based on motion direction
6. **Temporal Blend** - Incorporates frame history

## Integration Points

- `BlendMode.isCustom(_ mode: String) -> Bool` - Check for "Custom" prefix
- `BlendMode.random()` - Should include custom modes
- `ImageUtils.blend(layer:over:mode:opacity:)` - Routes to appropriate handler
- Per-source blend mode selection in UI

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

