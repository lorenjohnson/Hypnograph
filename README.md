<h1>
  <img src="website/assets/hypnograph-icon.png" alt="Hypnograph icon" width="88" align="left" />
  Hypnograph
</h1>

Hypnograph is a memory-forward visual instrument for macOS.

Instead of browsing your archive like a filing cabinet, Hypnograph turns your own photos and videos into an evolving stream of sequences you can watch, steer, compose, and perform. It begins in generative playback, but it is meant to become an instrument for rediscovery, authorship, and live visual use.

The app currently centers on:
- Generative playback and sequencing of local media
- Hypnogram composition through clip selection, timing, layering, blend modes, and effect chains
- Saving hypnograms to reopen, refine, and revisit later
- Rendering hypnograms out to video for playback and sharing
- Live preview and external-display performance workflows
- Optional Effects Composer for authoring and testing effects

If you want to try the current beta build, start at [hypnogra.ph](https://hypnogra.ph), which is the current public-facing entrypoint for the project.

## Development

Hypnograph is a macOS app built in Swift with SwiftUI and AppKit, using AVFoundation, Core Image, Metal, and Photos.

### Setup

Development prerequisites:
- This project uses a local Swift Package reference to `../HypnoPackages`.
- This project's product/documentation workflow also expects the sibling repo `../product-context-manager`.
- Product Context Manager: `https://github.com/lorenjohnson/product-context-manager.git`
- The intended setup is for all three repos to live as siblings:
  - `/path/to/dev/Hypnograph`
  - `/path/to/dev/HypnoPackages`
  - `/path/to/dev/product-context-manager`

Setup:
1. Clone this repository into your preferred development directory.
2. Change up one directory so you are in the parent folder that contains `Hypnograph`.
3. Clone `HypnoPackages` into that same parent folder.
4. Clone `product-context-manager` into that same parent folder.

Example:
1. `git clone https://github.com/lorenjohnson/Hypnograph.git`
2. `cd ..`
3. `git clone https://github.com/lorenjohnson/HypnoPackages.git`
4. `git clone https://github.com/lorenjohnson/product-context-manager.git`

Run:
1. Open [Hypnograph.xcodeproj](Hypnograph.xcodeproj) in Xcode 15+.
2. Select the `Hypnograph` scheme.
3. Build and run on macOS.

If your `HypnoPackages` path differs:
1. In Xcode, remove the existing local package reference to `../HypnoPackages`.
2. Re-add it via `File > Add Package Dependencies... > Add Local...` and pick your `HypnoPackages` folder.
3. Ensure `HypnoCore` / `HypnoUI` are linked on the `Hypnograph` target.

Website draft/dev preview:
1. `cd website`
2. `docker compose -f docker-compose.dev.yml up -d`
3. Open `http://localhost:8080`

### Repository Layout

- App source: [Hypnograph](Hypnograph)
- App tests: [HypnographTests](HypnographTests), [HypnographUITests](HypnographUITests)
- Project documentation: [docs](docs)
- Website: [website](website)

### Documentation

For app and product work, [docs](docs) is the main documentation workspace.

Useful entrypoints:
- Current work tracking: [docs/queue.md](docs/queue.md)
- Planned, not started: [docs/backlog](docs/backlog)
- Active project docs: [docs/active](docs/active)
- Completed project docs: [docs/archive](docs/archive)
- Reference docs: [docs/reference](docs/reference)

For website-specific dev work, start with [website/README.md](website/README.md).

If you're collaborating on the app, start in [docs](docs). Agent-specific routing and load-order rules live in `AGENTS.md`.
