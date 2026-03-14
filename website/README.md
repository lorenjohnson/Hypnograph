# Hypnograph Website

This directory contains the production website for `hypnogra.ph`.

Current site shape:
- single static page (`index.html`)
- single stylesheet (`styles.css`)
- nginx static serving via Docker

## Tech Stack

- Static HTML + CSS
- Nginx
- Docker Compose for local dev and Dokploy deploy

## Run Locally (Dev)

1. `cd website`
2. `docker compose -f docker-compose.dev.yml up -d`
3. Open `http://localhost:8080`

Stop local stack:
1. `cd website`
2. `docker compose -f docker-compose.dev.yml down`

## Deploy (Dokploy)

- Compose file: `docker-compose.dokploy.yml`
- Service: `hypnograph-site`
- Internal port: `80`

## Key Files

- Site entry: `index.html`
- Styles: `styles.css`
- Nginx config: `nginx.conf`
- Docker image definition: `Dockerfile`
