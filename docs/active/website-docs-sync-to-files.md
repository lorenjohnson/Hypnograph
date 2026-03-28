---
doc-status: in-progress
---
# Website Docs Sync To Files

1. Update `website/docker-compose.dokploy.yml` to add a one-shot `docs-sync` service with:
   - `../docs:/source-docs:ro`
   - `../files/docs:/docs`
2. In `docs-sync`, clear only the contents of `/docs` and copy `/source-docs/.` into `/docs` (`restart: "no"`).
3. Update `hypnograph-site` service to mount `../files/docs` as read-only and serve docs from that mount.
4. Gate site startup with `depends_on` + `condition: service_completed_successfully` so web starts after sync completes.
5. Keep homepage behavior as `index.html` loading `/docs/collaborators.md`.
6. Keep `/docs/*` routable so a URL like `/docs/active/<project>.md` can be fetched and rendered by the site.
7. In local dev, mirror the same pattern (sync into a local docs target dir, then serve from that target dir) so local and production behavior match.
8. Validate with `docker compose config` and local run that:
   - docs sync finishes successfully
   - site starts after sync
   - `/docs/collaborators.md` serves current content

You will do:
- In Dokploy Watch Paths, include both `website/**` and `docs/**`.

Why `../files/docs` (and no absolute host-path lookup):
- Dokploy documents bind-mount persistence for Docker Compose via the `../files/...` convention.
- Dokploy troubleshooting documents the compose project layout as `/application-name/code` and `/application-name/files`, and shows `../files/...` as the working mount pattern.
- We are not serving docs from `../docs` at runtime; we only use `../docs` as deploy-time source data for the sync step, and serve from the persistent `../files/docs` path.

References:
- https://docs.dokploy.com/docs/core/docker-compose
- https://docs.dokploy.com/docs/core/troubleshooting
