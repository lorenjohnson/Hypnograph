# Hypnograph Website

This directory contains the Hypnograph marketing/draft website.

Live site: [hypnogra.ph](https://hypnogra.ph)

## Tech Stack

- Static HTML pages (`index.html`, `features.html`, `showcase.html`)
- Vanilla CSS and JavaScript (`styles.css`, `app.js`)
- Nginx for serving static assets
- Docker Compose for local dev and Dokploy deploy
- Cloudflare Stream for hosted video playback

## Run Locally (Dev)

1. `cd website`
2. `docker compose -f docker-compose.dev.yml up -d`
3. Open `http://localhost:8080`

Stop local stack:
1. `cd website`
2. `docker compose -f docker-compose.dev.yml down`

## Deploy (Dokploy)

- Compose file: [docker-compose.dokploy.yml](docker-compose.dokploy.yml)
- Service: `hypnograph-site`
- Internal port: `80`
- Dokploy/Traefik should handle domain + TLS routing

## Directory Notes

- Static site entry: [index.html](index.html)
- Nginx config: [nginx.conf](nginx.conf)
- Docker image definition: [Dockerfile](Dockerfile)
- Assets: [assets](assets)

## Website Docs Routing

Website development docs live in [docs](docs). Start with [docs/README.md](docs/README.md).
