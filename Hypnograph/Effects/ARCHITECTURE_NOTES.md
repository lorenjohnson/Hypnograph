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

