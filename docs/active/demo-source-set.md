---
doc-status: draft
---

# Demo Source Set

## Overview

This project is about assembling and packaging a viable starter media set for Hypnograph from public-domain source material, so the first meaningful experience of the app does not depend on Apple Photos, optimized storage, or a user already having a large local archive of video.

The focus here is not to build a generalized "demo packs" feature system. The first goal is much narrower: curate and download a strong demo source set of public-domain clips, keep them lightweight enough to ship sensibly, package them into the app in the simplest acceptable way, and make them available as a default source from the start.

The interesting work is mostly curation rather than UI. The pack needs a clear flavor and enough visual variety to show what Hypnograph can do without overwhelming the app bundle or forcing the user into cloud-backed waiting states.

## Rules

- MUST keep the first pass focused on gathering, curating, downloading, and packaging starter media.
- MUST NOT expand the first pass into a broader downloadable-pack management feature unless the simpler packaging path clearly fails.
- MUST prefer the simplest viable in-app packaging and source-setup path for the initial version.
- MUST treat the public-domain curation itself as a product decision, not just an implementation detail.
- MUST keep bundle-size growth bounded enough that the starter pack still feels practical to ship.
- SHOULD bias toward lower-resolution clips if that materially reduces size without undermining the demo value.
- SHOULD prefer media that demonstrates Hypnograph's visual strengths while remaining broadly usable and depersonalized.

## Plan

- Smallest meaningful next slice: identify a few promising public-domain source collections and define the curation criteria for what counts as a good Hypnograph starter clip.
- Immediate acceptance check: there is a concrete plan for gathering a starter set that is visually strong, license-safe, and plausibly small enough to package.
- Follow-on slice: download and normalize an initial batch of candidate clips and estimate total bundle impact.
- Next slice after that: package the curated set in the simplest acceptable way and wire it up as a default source.

## Open Questions

- What clip count actually gives a good first-mile experience without bloating the app?
- What mix of subject matter feels most useful for Hypnograph: newsreels, nature footage, aerial footage, abstract motion, or some deliberate blend?
- How low can the resolution go before the pack starts undermining the visual quality of the product?
- Is the simplest packaging path acceptable for the first version, or does bundle size force a follow-on downloader workflow sooner than expected?
- Should the starter set be entirely video, or should it include some still-image material as well?
