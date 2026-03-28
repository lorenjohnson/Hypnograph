---
doc-status: ready
---

# Preview Frame Buffer Bleed Between Clips

## Overview

Preview sometimes shows temporal residue from the previous clip when switching clips or adjusting clip range/start, especially while temporal effects are active. The main symptom is that the newly viewed clip appears contaminated by prior clip history in preview, even though export/render output is usually correct. That makes this look primarily like a preview-pipeline state/isolation bug rather than a general render bug.

The issue is easiest to notice with effects such as `FrameDifference` and `IFrameCompress`, and it appears most often when rapidly moving between clips or making trim/start changes and replaying immediately. It can be intermittent, which makes the bug feel partly like a race or timing problem rather than a simple missed reset.

Several fixes have already been tried. Clearing frame-buffer state on clip switch and trim updates helped in some paths but did not eliminate the problem. Freezing outgoing effect context during transitions, including clip snapshot cloning, improved isolation in some cases but still left intermittent bleed. Timing and ordering adjustments around clip-switch reset and transition setup changed the symptom profile without resolving it. Additional temporal-generation guard attempts also did not fully fix it. Some of these attempts produced black-flash or cut artifacts during transitions, but that is not the primary bug for this project unless it turns out to share the same root cause.

Current suspicion is that preview temporal state is not being cleanly owned or invalidated across clip switches. The likely trouble spots are compositor requests that remain in flight while clips change, overlap between outgoing and incoming transition slots, and the exact timing of frame-history reset relative to transition startup.

## Plan

1. Reproduce the bug reliably in preview with temporal effects active, especially around previous/next navigation and trim/start changes.
2. Instrument and inspect preview state ownership during clip switches, focusing on:
   - `Hypnograph/App/Studio/Views/PlayerView.swift`
   - `Hypnograph/App/Studio/Views/PlayerContentView.swift`
   - `HypnoPackages/HypnoCore/Renderer/Core/FrameCompositor.swift`
   - `HypnoPackages/HypnoCore/Renderer/Display/RendererView.swift`
   - `HypnoPackages/HypnoCore/Renderer/Effects/Core/EffectManager.swift`
3. Determine whether the real failure is:
   - stale compositor work completing after a clip change
   - transition overlap leaking temporal state across slots
   - frame-history reset happening too early, too late, or on the wrong ownership boundary
4. Implement the smallest fix that fully isolates preview temporal state between clips.
5. Validate that:
   - no previous-clip bleed is visible in preview across clip navigation and trim/start edits with temporal effects active
   - preview behavior matches export/render behavior for the tested scenarios
   - the fix does not introduce new transition artifacts unless that tradeoff is explicitly accepted
