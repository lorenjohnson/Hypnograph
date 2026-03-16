<h1>
  <img src="website/assets/hypnograph-icon.png" alt="Hypnograph icon" width="88" align="left" />
  Hypnograph
</h1>

Hypnograph is a memory-forward visual instrument for macOS.

Instead of browsing your archive like a filing cabinet, Hypnograph replays your photos and videos as evolving, remixable sequences. The product goal is to make revisiting your captured life feel exploratory, reflective, and creatively useful.

[Live website: hypnogra.ph](https://hypnogra.ph)

[![Watch Hypnograph teaser](https://customer-ol1nnrpowobo4pog.cloudflarestream.com/6948b43abd96d022bccc2228064ceecd/thumbnails/thumbnail.jpg)](https://customer-ol1nnrpowobo4pog.cloudflarestream.com/6948b43abd96d022bccc2228064ceecd/watch)

[View additional preview screenshots](website/hero-preview.png)

If you're joining as a developer collaborator: this is an app for generative playback, effect-driven transformation, live visual experimentation, and export of resulting "hypnograms."

The app currently centers on:
- Generative playback and sequencing of local media
- Effect-chain based visual processing (Core Image + Metal)
- Playback, live preview, and export workflows

## Tech Snapshot

- Platform: macOS 14+
- Language/UI: Swift 5.9+, SwiftUI + AppKit
- Core frameworks: AVFoundation, CoreImage, Metal, Photos
- Build tool: Xcode project (`Hypnograph.xcodeproj`)

## Quick Start (Dev)

Prerequisite layout (important):
- This project uses a local Swift Package reference to `../HypnoPackages`.
- The easiest setup is to clone both repos as siblings:
  - `/path/to/dev/Hypnograph`
  - `/path/to/dev/HypnoPackages`

Bootstrap:
1. `cd /path/to/dev`
2. `git clone https://github.com/lorenjohnson/Hypnograph.git`
3. `git clone https://github.com/lorenjohnson/HypnoPackages.git`

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

## Unsigned macOS Release (No Apple Developer Program)

If Apple Developer Program enrollment is blocked, you can still ship a direct download
that users can install manually.

Build release artifacts:
1. Open this project in Xcode and verify `Hypnograph` builds in `Release`.
2. From repo root, run: `./scripts/release-macos-unsigned.sh`
3. Upload files in `dist/` to your download page or GitHub Release.

Generated artifacts:
- `Hypnograph-<version>-<build>-macOS-unsigned.dmg`
- `Hypnograph-<version>-<build>-macOS-unsigned.zip`
- `Hypnograph-<version>-<build>-macOS-unsigned.sha256`

Installer guidance for users:
1. Download and open the `.dmg`.
2. Drag `Hypnograph.app` to `Applications`.
3. First launch: right-click the app and choose `Open`, then confirm in the warning dialog.

Notes:
- This path does not use TestFlight or notarization.
- Gatekeeper will show a warning because the app is unsigned/not notarized.
- This is acceptable for friend beta distribution with clear install instructions.

## Repository Layout

- App source: [Hypnograph](Hypnograph)
- App tests: [HypnographTests](HypnographTests), [HypnographUITests](HypnographUITests)
- Website draft: [website](website)
- App/project documentation: [docs](docs)
- Website development documentation: [website/docs](website/docs)

## Documentation Routing (Important)

For app/product work, docs live in [docs](docs), and documentation work should follow [docs/README.md](docs/README.md).

Use this routing:
- Current work tracking: [docs/roadmap.md](docs/roadmap.md)
- Planned, not started: [docs/backlog](docs/backlog)
- Active project docs: [docs/active](docs/active)
- Completed project docs: [docs/archive](docs/archive) (filename format: `YYYYMMDD-project-name.md`)
- Completed roadmap items without dedicated project docs: [docs/archive/done.md](docs/archive/done.md)

For website-specific dev work, use [website/docs](website/docs) and start with [website/docs/README.md](website/docs/README.md), which follows the same roadmap/backlog/active/archive lifecycle.

If you're a collaborator or an LLM agent, start with the relevant docs README before creating or moving documentation.
