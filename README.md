# Media Server Stack

Docker Compose stack for Plex, *arr apps, qBittorrent, Ombi, Nginx, and supporting services. Uses `.env` for host paths and IDs, and an installer to create required folders.

## Prereqs

- Docker installed and running
- Docker Compose plugin available (`docker compose`)

## Quick start

```bash
git clone <repo-url>
cd media-server
cp .env.example .env
# Edit .env to match your paths and user IDs
./scripts/install.sh
docker compose ps
```

## Troubleshooting

- MEDIA_ROOT mount: ensure your media path is actually mounted.
  - `mount | grep "$MEDIA_ROOT"`
  - `ls -la "$MEDIA_ROOT"`
- Port conflicts: if preflight reports a busy port, stop the conflicting process or change the binding.
- Permissions (PUID/PGID): containers write as the user/group you set in `.env`.
  - `id -u` / `id -g`
  - `sudo chown -R $PUID:$PGID $CONFIG_ROOT`

## Ports and URLs

The table below lists direct ports and optional nginx path proxies. The nginx
path URLs work when you include the templates under `configs/_templates/nginx/conf.d`
in your nginx `server` block.

Minimal example (HTTP only):

```nginx
server {
  listen 80;
  server_name _;
  include /etc/nginx/conf.d/*.conf;
}
```

The templates proxy by path (for example `/radarr`, `/sonarr`, `/qbit`, etc.).
DNS is optional; accessing by IP works.

| Service     | Default port | Example URL                    | Nginx path |
|-------------|--------------|--------------------------------|------------|
| Plex        | 32400        | http://localhost:32400/web     | /plex      |
| qBittorrent | 8080         | http://localhost:8080          | /qbit      |
| Jackett     | 9117         | http://localhost:9117          | N/A        |
| Radarr      | 7878         | http://localhost:7878          | /radarr    |
| Sonarr      | 8989         | http://localhost:8989          | /sonarr    |
| Bazarr      | 6767         | http://localhost:6767          | /bazarr    |
| Ombi        | 3579         | http://localhost:3579          | /ombi      |
| Portainer   | 9000         | http://localhost:9000          | /portainer |
| Nginx       | 80/443       | http://localhost               | N/A        |

## Runtime folder contract (CONFIG_ROOT)

The installer creates the canonical directory structure under `CONFIG_ROOT` and
never overwrites existing files or directories.

```
CONFIG_ROOT/
  bazarr/
  jackett/
  nginx/
    certs/
    conf.d/
  ombi/
  plex/
  portainer/
  qBittorrent/
  radarr/
  sonarr/
```

## Directory purpose

- `bazarr/`: persistent configuration and app data for Bazarr.
- `jackett/`: persistent configuration and app data for Jackett.
- `nginx/`: parent directory for Nginx configuration and TLS assets.
- `nginx/certs/`: TLS certificates and keys used by Nginx.
- `nginx/conf.d/`: Nginx vhost and reverse-proxy configuration snippets.
- `ombi/`: persistent configuration and app data for Ombi.
- `plex/`: persistent configuration and app data for Plex.
- `portainer/`: persistent data for Portainer.
- `qBittorrent/`: persistent configuration and app data for qBittorrent.
- `radarr/`: persistent configuration and app data for Radarr.
- `sonarr/`: persistent configuration and app data for Sonarr.

## Security notes

- Mounting `/var/run/docker.sock` (Portainer/Watchtower) grants admin control of Docker; keep access restricted.
- Plex uses host networking, which reduces container isolation; avoid exposing it beyond your LAN.
- Prefer firewall rules or LAN-only access for all service ports.

## What this installer does NOT do

- It does not configure apps (Radarr/Sonarr/etc.); you must complete setup in each UI.
- It does not download media for you.
- It does not set up DNS or HTTPS automatically.

## First-time app setup order

1) qBittorrent
2) Jackett
3) Radarr / Sonarr
4) Bazarr
5) Plex
6) Ombi

## Watchtower note

Watchtower automatically updates running containers. This is convenient, but it can introduce unexpected changes; you may want to disable it for stability.

Ways to disable it:
- Comment out the `watchtower` service in `compose.yml`
- Set `WATCHTOWER_*` variables to limit or disable updates
- Stop the container with `docker compose stop watchtower`
