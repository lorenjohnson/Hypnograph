---
doc-status: in-progress
---
# Holocron Docs Publishing

## Overview

Replace the current custom website documentation renderer with Holocron, using Holocron's Vite/plugin defaults as much as possible while preserving the repo-first documentation workflow.

The current site publishes documentation through a small ad hoc static app in `website/`: custom Markdown fetching, nginx directory listing, client-side route mapping, sidebar tree generation, interval refresh, and hand-maintained rendering behavior. This works, but it is too much local apparatus for a docs surface.

The intended delta is to remove that custom docs publishing system and let Holocron own the documentation site experience. The home page still needs to introduce Hypnograph clearly and provide a prominent beta/download entrypoint. The deployment path still needs to work through the existing Dokploy setup, with this branch deployable for testing before replacing the current site.

## Scope

- MUST keep the repository as the source of truth for documentation.
- MUST fully replace the current ad hoc docs renderer rather than keeping parallel publishing systems.
- MUST preserve or recreate the current public home-page role: product introduction plus a prominent download/beta link.
- MUST keep Dokploy deployment viable and testable from this branch before merge.
- MUST keep Holocron configuration as simple as practical, leaning into Holocron defaults.
- MUST publish the whole `docs/` tree by default unless a document is explicitly excluded later.
- MUST NOT require hand-maintained Holocron navigation updates every time a local document is created.
- SHOULD support the normal local workflow where new docs are created or edited locally, committed, pushed, and then published.
- SHOULD generate Holocron navigation from the `docs/` tree during the publish/deploy path so local document creation stays low-friction.
- SHOULD make generated navigation deterministic and reviewable.
- MAY add a safeguard that fails publish if generated navigation is stale, or a publish-time generator that writes the navigation before build.
- MUST NOT add legacy compatibility code for the old docs renderer.
- MUST NOT preserve the old custom website JavaScript/nginx docs tree behavior once Holocron replaces it.

## Plan

Smallest meaningful next slice:

1. Confirm Holocron's minimum project shape for this repo: package setup, generated `docs.json`, page directory, homepage support, and build output/runtime expectations.
2. Replace the website app with a Holocron/Vite site under `website/`, keeping the homepage product introduction, beta download CTA, and demo-video entrypoint.
3. Generate Holocron navigation from the whole `docs/` tree during `npm run dev` and `npm run build`; generated config and copied MDX-safe pages stay out of Git.
4. Update the Dokploy deployment files so the branch can deploy the Holocron site in place of the current website service.
5. Remove the old ad hoc renderer once the Holocron path builds and the Dokploy branch deploy is confirmed.

Immediate acceptance check:

- Local Holocron dev/build works without Xcode.
- The home page introduces Hypnograph and has a prominent beta/download link.
- Existing documentation pages render through Holocron rather than the old `website/app.js` renderer.
- A newly added local doc can be made visible in the Holocron navigation through the chosen workflow.
- Dokploy can deploy this branch and serve the replacement site at the same public entrypoint.

## Open Questions

- Later, if Holocron cloud editing is enabled, what explicit rule ensures cloud edits are pushed back to Git before they are considered durable?

## Implementation Notes

- `website/scripts/generate-holocron-config.mjs` generates `website/docs.json` and `.holocron-pages/` from the repo docs at dev/build time.
- Source docs are not rewritten for Holocron. The generated copy normalizes MDX-sensitive Markdown autolinks before Holocron reads them.
- `@holocron.so/vite` 0.17.0 handles repo-internal `.md` / `.mdx` page links through its own MDX normalization, preserving raw `.md` endpoints while rendering internal docs navigation correctly.
- Holocron 0.17.0 does not expose a config flag to hide inline section headings in the left navigation; `website/global.css` hides only that generated inline TOC while preserving the document tree.
- `logo.text` now renders the Hypnograph wordmark through Holocron config instead of a local `.slot-logo::after` CSS workaround.
- The Documentation and Development tabs use Holocron's native tab `pages` shorthand; generated child groups still preserve the repo docs tree under Development.
- Redirects are limited to current convenience entrypoints (`/docs`, `/docs/user-manual`); old pre-Holocron URL preservation redirects were removed.
- `website/Dockerfile` now builds and serves the Holocron site with Node rather than nginx and the removed custom renderer.
- `website/docker-compose.dokploy.yml` uses the repo root as Docker context so both `website/` and `docs/` are available during build.
