---
created: 2026-03-14
updated: 2026-03-17
---

<div class="collab-hero">
  <img src="/docs/assets/hypnograph-icon.png" alt="Hypnograph icon" class="collab-hero-icon" />
  <div class="collab-hero-text">
    <h1 class="collab-hero-title">Hypnograph</h1>
    <p class="collab-hero-kicker">Memory-forward visual instrument for macOS</p>
  </div>
</div>

Instead of browsing your archive like a filing cabinet, Hypnograph replays your photos and videos as evolving, remixable sequences. It can begin in a generative mode where surprising combinations emerge quickly, and it can also be steered into deliberate composition through clip selection, timing, layering, blend modes, and effect chains.

The point is not to generate synthetic media. The point is to re-encounter material that already belongs to your life or project and shape it into something that feels newly alive, exploratory, and creatively useful.

What Hypnograph should become from here depends on real use. This document is part of that process.

<div id="homepage-screencast-lightbox" class="video-lightbox" aria-hidden="true">
  <div class="video-lightbox-panel" role="dialog" aria-modal="true" aria-label="Hypnograph screencast player">
    <button type="button" class="video-lightbox-close" data-video-lightbox-close aria-label="Close video">&times;</button>
    <iframe
      title="Hypnograph Screencast"
      class="video-lightbox-frame"
      data-video-embed-src="https://iframe.videodelivery.net/741c294e44de4589ea5e1761601db44a?autoplay=true&controls=true"
      allow="accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture"
      allowfullscreen
      loading="lazy"></iframe>
  </div>
</div>

<div class="beta-grid">
  <div class="beta-inset beta-demo">
    <h3>Watch a Demo Session</h3>
    <button type="button" class="video-thumbnail-button" data-video-lightbox-open="homepage-screencast-lightbox" aria-label="Play Hypnograph demo session">
      <img src="https://customer-ol1nnrpowobo4pog.cloudflarestream.com/741c294e44de4589ea5e1761601db44a/thumbnails/thumbnail.jpg" alt="Hypnograph screencast preview frame" class="video-thumbnail-image" />
      <span class="video-thumbnail-play" aria-hidden="true"></span>
    </button>
  </div>

  <div class="beta-inset beta-download">
    <h3>Download the Beta</h3>
    <p><a href="https://github.com/lorenjohnson/Hypnograph/releases/download/v0.2.2-beta1/Hypnograph-0.2-2-macOS-unsigned.dmg">Download current DMG (v0.2 build 2)</a></p>
    <p>Apple Silicon only (M-series).</p>
    <p>Install: open the DMG, drag <code>Hypnograph.app</code> to <code>Applications</code>, then first launch via right-click <code>Open</code>.</p>
  </div>
</div>

Hypnograph is at a turning point where I need to sharpen what the app actually is by grounding it in real use, not only in internal iteration. The immediate need is to involve a small set of collaborators who can work with what already exists, use it seriously, and reflect back what feels meaningful, confusing, exciting, or missing in expected behavior.

In this stage, I'm most needing contribution in the form of folks trying it out and giving feedback to help focus and shape the tool. Careful rounds of use and feedback: what people try to do with the app, what they expect it to do, what it already does well, and where the tool can be narrowed or deepened.

The use cases below are the working foundation for that process, and will likely be shaped by your own feedback. For now they help identify who to invite, what sessions to run, and what product direction to prioritize while keeping authorship coherent and open to new ideas from people whose use feels relatable and concrete.

<div class="use-case-card">
  <h2>Use Case 1: Personal Archive Exploration and Immersion</h2>
  <h3>Scenario</h3>
  <p>Use Hypnograph with your own photo and video history as a creative-reflective practice: move through personal archives, surface forgotten or overlooked material, and re-encounter your own past as something present and alive.</p>
  <p>In this mode, playback can feel like watching your own life as a nonlinear "channel" in a default-mode-network kind of space: less task-driven searching, more open attention and pattern recognition.</p>
  <h3>What Already Works Well</h3>
  <ul>
    <li>Randomized playback turns static archives into living sequences with rhythm and emotional texture.</li>
    <li>The "channel" feel supports rediscovery, not just retrieval: less folder browsing, more felt meaning.</li>
    <li><code>Mark for deletion</code>: a single key can flag current media to a staged deletion flow (kept in the <code>Deleted</code> album under the <code>Hypnograph</code> folder in Apple Photos for later review).</li>
    <li><code>Exclude</code>: permanently removes a clip from randomized playback without deleting it.</li>
    <li><code>Favorite</code>: saves standout clips into the <code>Favorites</code> album under the <code>Hypnograph</code> folder in Apple Photos.</li>
  </ul>
  <h3>Gaps</h3>
  <ul>
    <li>First-run Photos authorization still needs to feel smoother and more predictable in beta builds.</li>
    <li>Library/source state should become more transparent during initial setup so users know what is happening.</li>
    <li>Onboarding guidance for first-mile curation (favorite/exclude/delete) needs to be clearer in-app.</li>
  </ul>
</div>

<div class="use-case-card">
  <h2>Use Case 2: Fresh-Off-the-Shoot Footage Exploration</h2>
  <h3>Scenario</h3>
  <p>After a shoot (for example, a short film with a large footage set), use Hypnograph early in the edit process to rapidly explore combinations of clips with smooth, cinematic-style transitions.</p>
  <p>The randomized sequencing often places shots together that would not normally be considered in a first pass. Some juxtapositions are clearly wrong, and some are unexpectedly strong. Both outcomes are useful: they accelerate editing intuition and story discovery.</p>
  <h3>What Already Works Well</h3>
  <ul>
    <li>Randomized playback creates quick adjacency tests across many clips.</li>
    <li>Global clip length and source sectioning support structured experimentation.</li>
    <li>Layering and effect chains support early visual direction finding.</li>
    <li>Output can be reviewed immediately for candidate edit ideas.</li>
  </ul>
  <h3>Gaps</h3>
  <ul>
    <li>Per-layer rotation controls are missing. Rotate in 90-degree increments per layer would be nice. Consider other options.</li>
    <li>Rendering multiple clips in sequence, including transitions between clips, is still missing as an integrated UI workflow.</li>
    <li>No clear playback playhead indicator in layer scrubbing/timeline views.</li>
    <li>No quick, intuitive frame-by-frame stepping workflow.</li>
    <li>Missing a quick way (menu and/or keyboard based) for setting in/out-point of clips or global.</li>
    <li>Global clip-length behavior is asymmetrical: reducing global length appears to reduce effective layer selection lengths, while increasing it currently leaves layer selections unchanged. Try global clip length expansion by default also expanding all layers.</li>
  </ul>
</div>

<div class="use-case-card">
  <h2>Use Case 3: Create Shorts for Social Media</h2>
  <h3>Scenario</h3>
  <p>Start from a recently shot clip available locally or in Apple Photos, process it in Hypnograph, and export a short expressive piece for Instagram Story/Reel style posting.</p>
  <h3>What Already Works Well</h3>
  <ul>
    <li>This is one of the better-provisioned workflows in the current beta.</li>
    <li>Clip selection, layering, and effects can produce expressive short-form output quickly.</li>
    <li>The flow from source clip to stylized export is already viable for collaborator testing.</li>
  </ul>
  <h3>Gaps</h3>
  <ul>
    <li>The workflow needs clearer presets/templates for common social formats and aspect ratios.</li>
    <li>Export intent could be made more obvious with simpler "ready to post" defaults.</li>
    <li>This area is intentionally lower priority than personal archive and post-shoot discovery use cases.</li>
  </ul>
</div>
