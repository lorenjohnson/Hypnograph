# Effect Architecture Notes

## TL;DR - Standard Formats for Video Filters

**YES! There IS a standard format: ISF (Interactive Shader Format)**

- **Website**: https://isf.video/
- **Spec**: https://github.com/mrRay/ISF_Spec
- **License**: MIT (completely open source)
- **Format**: GLSL fragment shaders with JSON metadata
- **Supported by**: VDMX, Resolume, TouchDesigner, Max/MSP, and many others
- **Library**: 200+ free open-source shaders available

### Why ISF Exists (But Doesn't Fit Your Use Case)

ISF is designed for **real-time VJ/live video performance**, not video file export:
- ✅ Perfect for: Live video mixing, VJ software, real-time effects
- ❌ Not ideal for: Video file export, AVFoundation pipelines
- Uses: GLSL shaders (OpenGL/WebGL/Metal)
- Your system uses: CoreImage filters + AVVideoComposition

### Could You Use ISF?

**Technically yes, but it would require significant work:**
1. Parse ISF JSON metadata
2. Transpile GLSL to Metal or CoreImage kernels
3. Map ISF inputs to your RenderContext
4. Handle multi-pass rendering
5. Manage persistent buffers

**Is it worth it?** Probably not for your use case. ISF is optimized for live performance, not video export.

---

# Solo Mode Feature

## Summary

Added per-source solo mode toggle for Montage mode. When solo is active, only the selected layer is displayed in the preview, **with both per-source and global effects correctly applied**.

## Implementation

### Changes Made:

1. **MontageMode.swift**:
   - Solo mode was already partially implemented with `soloLayerIndex` property
   - Added `toggleSolo()` method to protocol interface
   - Solo automatically clears when switching layers (via `nextSource()`, `previousSource()`, `selectSource()`)
   - Solo clears when creating new hypnogram or saving current one
   - Added solo status to HUD display
   - Modified `layersForDisplay()` to return both layers and their original source indices

2. **HypnographMode.swift**:
   - Added `toggleSolo()` to protocol

3. **HypnographApp.swift**:
   - Added keyboard shortcut: **S = Solo Current Source**

4. **MultiLayerBlendInstruction.swift**:
   - Added `sourceIndices` array to track original layer indices
   - This ensures per-source effects are applied to the correct source even when solo filtering changes layer positions

5. **MultiLayerBlendCompositor.swift**:
   - Updated to use `sourceIndices` when applying per-source effects
   - Now uses original source index instead of track position for effect lookup

6. **MontageView.swift**:
   - Added `sourceIndices` parameter
   - Passes source indices through to compositor instruction

7. **MontageRenderer.swift**:
   - Generates sequential source indices for full renders (no solo filtering)

### Behavior:

- **Press S**: Toggle solo for current layer
  - If solo is off → solo current layer (only that layer displays)
  - If solo is on for current layer → turn solo off (all layers display)
  - If solo is on for different layer → switch solo to current layer

- **Effects in Solo Mode**:
  - ✅ Per-source effects are correctly applied to the soloed layer
  - ✅ Global effects continue to work on the final output
  - The original source index is preserved through the rendering pipeline

- **Solo automatically clears when**:
  - Switching to another layer (arrow keys, 1-5 keys)
  - Creating new random hypnogram (Space)
  - Saving current hypnogram (Cmd-S)
  - Reloading settings (Cmd-R)

- **HUD Display**:
  - Shows "SOLO: Source N" in bold when solo is active

### Technical Details:

The key challenge was that when you solo layer 2, it becomes index 0 in the filtered layer array, but we need to apply the effect configured for source 2, not source 0.

**Solution**: Track original source indices through the entire pipeline:
1. `MontageMode.layersForDisplay()` returns `(layers, sourceIndices)` tuple
2. `MontageView` passes `sourceIndices` to `MultiLayerBlendInstruction`
3. `MultiLayerBlendCompositor` uses `sourceIndices[trackPosition]` to look up the correct per-source effect

### Keyboard Shortcuts:

- **S** = Solo current source (toggle)
- **←/→** = Previous/Next source (clears solo)
- **1-5** = Select source (clears solo)

---

# Effect Architecture Notes

## Why CoreImage Instead of SwiftUI Shaders?

### SwiftUI Shaders (Inferno's Approach)
**Use case**: Real-time UI effects on SwiftUI views

**Pros**:
- Easy to apply to any SwiftUI view
- Great for interactive UI
- Simple API (`.colorEffect()`, `.layerEffect()`)
- Perfect for buttons, text, backgrounds

**Cons**:
- Cannot be used in video export pipeline
- No access to AVFoundation video composition
- No frame buffer for temporal effects
- UI-only, not for video processing

**Example**:
```swift
Text("Hello")
    .colorEffect(ShaderLibrary.rgbSplit(.float(10)))
```

### CoreImage Filters (Our Approach)
**Use case**: Video frame processing and export

**Pros**:
- Works with AVVideoComposition for export
- Can process CIImage from video frames
- Access to frame buffer for temporal effects
- Same code works for preview AND export
- Integrates with MultiLayerBlendCompositor

**Cons**:
- More verbose than SwiftUI shaders
- Limited to CoreImage's filter capabilities
- Slightly less performant than custom Metal

**Example**:
```swift
struct MyEffect: RenderHook {
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        // Process video frame
        return processedImage
    }
}
```

### Custom Metal Kernels (Advanced Hybrid)
**Use case**: Custom GPU effects for video processing

**Pros**:
- Maximum performance
- Custom effects not possible with CoreImage
- Still works with video export
- Full control over GPU computation

**Cons**:
- Complex setup (write Metal, compile .metallib)
- Requires Metal knowledge
- More code to maintain

**Example**:
```swift
// 1. Write Metal kernel (.metal file)
extern "C" float4 myEffect(sampler src) {
    // Custom GPU code
}

// 2. Load and apply in Swift
let kernel = try CIKernel(functionName: "myEffect", fromMetalLibraryData: data)
let output = kernel.apply(extent: extent, arguments: [image])
```

## Our Current Architecture

```
Video Frame (CVPixelBuffer)
    ↓
CIImage
    ↓
RenderHook.willRenderFrame() ← You are here
    ↓
CoreImage Filters (CIFilter)
    ↓
Processed CIImage
    ↓
AVVideoComposition
    ↓
Exported MP4
```

## When to Use Each Approach

### Use SwiftUI Shaders When:
- Building UI effects (buttons, text, backgrounds)
- Need real-time interactive effects
- Don't need to export to video
- Want simple API

### Use CoreImage Filters When:
- Processing video frames
- Need to export to video files
- Need temporal effects (frame buffer)
- Want preview + export with same code ← **This is us!**

### Use Custom Metal Kernels When:
- Need maximum performance
- CoreImage filters can't do what you need
- Still need video export capability
- Have Metal expertise

## Could We Port Inferno Shaders?

**Yes, but it requires work:**

1. Extract the Metal shader code from Inferno
2. Adapt it to work with CoreImage's CIKernel API
3. Compile into .metallib
4. Load at runtime in RenderHook
5. Apply to CIImage

**Is it worth it?**
- For simple effects (RGB split, scanlines): No, CoreImage is fine
- For complex effects (custom distortions, noise): Maybe
- For performance-critical effects: Yes

## Recommendation

**Stick with CoreImage filters for now** because:
1. ✅ They work perfectly with your video pipeline
2. ✅ Simple to implement and maintain
3. ✅ Good enough performance for most effects
4. ✅ Can always upgrade to custom Metal later if needed

**Consider custom Metal kernels if**:
1. You need effects CoreImage can't do
2. Performance becomes an issue
3. You want to learn Metal shader programming

