//
//  TimeShuffleShader.metal
//  Hypnograph
//
//  Time shuffle - swap chunks of frames out of order.
//  Different screen regions show different temporal chunks.
//  Creates organic "scrambled tape" degradation.
//

#include <metal_stdlib>
using namespace metal;

struct TimeShuffleParams {
    int textureWidth;
    int textureHeight;
    int numRegions;         // How many regions to divide screen into (2-8)
    int chunkSize;          // Minimum frames per chunk (15+)
    int maxHistoryFrames;   // Available frame buffer depth
    uint shuffleSeed;       // Changes when shuffle happens
};

// Simple hash for region assignment
inline uint regionHash(int regionIndex, uint seed) {
    uint h = uint(regionIndex) * 2654435761u + seed;
    h = (h ^ (h >> 13)) * 1274126177u;
    return h ^ (h >> 16);
}

kernel void timeShuffleKernel(
    array<texture2d<float, access::read>, 8> historyTextures [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(8)]],
    constant TimeShuffleParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    int width = params.textureWidth;
    int height = params.textureHeight;
    
    if (gid.x >= uint(width) || gid.y >= uint(height)) {
        return;
    }
    
    // Determine which region this pixel belongs to
    // Use horizontal bands for VHS-like effect
    int numRegions = clamp(params.numRegions, 2, 8);
    int regionHeight = height / numRegions;
    int regionIndex = min(int(gid.y) / max(regionHeight, 1), numRegions - 1);
    
    // Hash determines which temporal chunk this region shows
    uint hash = regionHash(regionIndex, params.shuffleSeed);
    
    // Map hash to a chunk index (0 to 7 for our 8 textures)
    int chunkIndex = int(hash % 8);
    
    // Read from the assigned temporal chunk
    float4 result = historyTextures[chunkIndex].read(gid);

    outputTexture.write(result, gid);
}

