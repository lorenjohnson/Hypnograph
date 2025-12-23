//
//  BasicShader.metal
//  Hypnograph
//
//  Basic image adjustments: opacity, contrast, brightness, saturation, hue.
//  All adjustment parameters use -1 to 1 scale (0 = no change) except opacity (0-1).
//

#include <metal_stdlib>
using namespace metal;

// Parameters passed from Swift - must match BasicParamsGPU
struct BasicParams {
    float opacity;       // 0.0 = transparent, 1.0 = fully opaque
    float contrast;      // -1 to 1: 0 = no change, -1 = flat, 1 = high contrast
    float brightness;    // -1 to 1: 0 = no change, -1 = black, 1 = white
    float saturation;    // -1 to 1: 0 = no change, -1 = grayscale, 1 = oversaturated
    float hueShift;      // -1 to 1: rotates hue (-1 = -180°, 0 = no change, 1 = +180°)
    int textureWidth;
    int textureHeight;
};

// RGB to HSV conversion
float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB conversion
float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// MARK: - Basic Adjustment Kernel

kernel void basicKernel(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant BasicParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= uint(params.textureWidth) || gid.y >= uint(params.textureHeight)) {
        return;
    }

    // Sample input texture
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 uv = float2(gid) / float2(params.textureWidth, params.textureHeight);
    float4 color = inputTexture.sample(textureSampler, uv);

    float3 rgb = color.rgb;

    // Apply contrast: map -1..1 to 0.5..2.0 multiplier
    // -1 = 0.5x (flat), 0 = 1.0x (no change), 1 = 2.0x (high contrast)
    float contrastMult = 1.0f + params.contrast;  // Maps -1..1 to 0..2
    contrastMult = clamp(contrastMult, 0.5f, 2.0f);
    rgb = (rgb - 0.5f) * contrastMult + 0.5f;

    // Apply brightness: map -1..1 to -0.5..0.5 offset
    float brightnessOffset = params.brightness * 0.5f;
    rgb += brightnessOffset;

    // Apply saturation: mix with luminance
    // -1 = grayscale, 0 = no change, 1 = 2x saturation
    float luma = dot(rgb, float3(0.299f, 0.587f, 0.114f));
    float satMult = 1.0f + params.saturation;  // Maps -1..1 to 0..2
    satMult = clamp(satMult, 0.0f, 2.0f);
    rgb = mix(float3(luma), rgb, satMult);

    // Apply hue shift (convert to HSV, rotate hue, convert back)
    if (abs(params.hueShift) > 0.001f) {
        float3 hsv = rgb2hsv(rgb);
        hsv.x = fract(hsv.x + params.hueShift * 0.5f);  // -1..1 maps to -0.5..0.5 rotation
        rgb = hsv2rgb(hsv);
    }

    // Clamp to valid range
    rgb = clamp(rgb, 0.0f, 1.0f);

    // Apply opacity to alpha channel
    float alpha = color.a * clamp(params.opacity, 0.0f, 1.0f);

    // Write to output
    outputTexture.write(float4(rgb, alpha), gid);
}

