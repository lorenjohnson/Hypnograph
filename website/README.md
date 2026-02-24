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

1. `cd /Users/lorenjohnson/dev/Hypnograph/website`
2. `docker compose -f docker-compose.dev.yml up -d`
3. Open `http://localhost:8080`

Stop local stack:
1. `cd /Users/lorenjohnson/dev/Hypnograph/website`
2. `docker compose -f docker-compose.dev.yml down`

## Deploy (Dokploy)

- Compose file: [docker-compose.dokploy.yml](/Users/lorenjohnson/dev/Hypnograph/website/docker-compose.dokploy.yml)
- Service: `hypnograph-site`
- Internal port: `80`
- Dokploy/Traefik should handle domain + TLS routing

## Directory Notes

- Static site entry: [index.html](/Users/lorenjohnson/dev/Hypnograph/website/index.html)
- Nginx config: [nginx.conf](/Users/lorenjohnson/dev/Hypnograph/website/nginx.conf)
- Docker image definition: [Dockerfile](/Users/lorenjohnson/dev/Hypnograph/website/Dockerfile)
- Assets: [assets](/Users/lorenjohnson/dev/Hypnograph/website/assets)

## Website Docs Routing

Website development docs live in [website/docs](/Users/lorenjohnson/dev/Hypnograph/website/docs). Start with [website/docs/README.md](/Users/lorenjohnson/dev/Hypnograph/website/docs/README.md).
