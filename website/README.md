# Hypnograph Website

This directory contains the production website for `hypnogra.ph`.

Current site shape:
- Holocron docs site built with Vite
- home page content in `index.md`
- generated Holocron navigation from the repository `docs/` tree
- Node runtime for local/Dokploy deployment

## Run Locally

Install dependencies:

1. `cd website`
2. `npm install`

Development server:

1. `npm run dev`
2. Open `http://localhost:5173`

Production build and run:

1. `npm run build`
2. `npm run start`
3. Open `http://localhost:3000`

Docker dev preview:

1. `docker compose -f docker-compose.dev.yml up -d`
2. Open `http://localhost:8080`

## Deploy

Dokploy uses `docker-compose.dokploy.yml`.

The container builds the Holocron site from this branch and serves the Node runtime on internal port `3000`.

## Key Files

- Holocron config generator: `scripts/generate-holocron-config.mjs`
- Generated Holocron config: `docs.json`
- Vite config: `vite.config.ts`
- Homepage content: `index.md`
- Homepage/custom style overrides: `global.css`
- Docker image definition: `Dockerfile`
