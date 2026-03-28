---
doc-status: done
---

# Website Docs Sync To Files

## Overview

This project started as a Dokploy-side docs-sync plan, but the simpler solution is what actually landed and appears to be working correctly in practice.

Production now builds the website image from the repo root and bakes the current `docs/` tree directly into the image as `/docs`. Local dev mirrors the same effective result by bind-mounting `../docs` into `/docs`.

That means the website can route and render the current project/reference docs without a separate runtime sync container, and the deployed behavior matches the current repo state at image-build time.

## Completion Notes

What is true now:
- [Dockerfile](/Users/lorenjohnson/dev/Hypnograph/website/Dockerfile) is built from repo root via [docker-compose.dokploy.yml](/Users/lorenjohnson/dev/Hypnograph/website/docker-compose.dokploy.yml).
- That Dockerfile does `COPY docs /docs`, so production docs are captured at image-build time.
- [docker-compose.dev.yml](/Users/lorenjohnson/dev/Hypnograph/website/docker-compose.dev.yml) mounts `../docs:/docs:ro`, so local development sees the current docs tree directly.
- [nginx.conf](/Users/lorenjohnson/dev/Hypnograph/website/nginx.conf) serves `/docs/*` from `/docs/`.
- [app.js](/Users/lorenjohnson/dev/Hypnograph/website/app.js) routes doc paths and homepage behavior as expected.

So the original one-shot `docs-sync` service described in the active draft is no longer needed to satisfy the real goal of the project.

## Review Notes

- The project is complete, but the implementation path differs from the original plan.
- Docs are refreshed on production deploy when Dokploy rebuilds the image, not via a separate runtime copy step.
- If Dokploy watch paths are configured to rebuild on both `website/**` and `docs/**`, that remains the operational detail worth keeping in place.
