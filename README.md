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

During first setup, open each app on its direct port and set the Base URL in
the app UI when required (Plex, Portainer, and qBittorrent do not need this).
The table below is for the initial setup URLs (use `http://SERVER_IP:PORT`),
then switch to the nginx paths after saving the Base URL.

The landing page is available at `http://SERVER_IP/`.

| App         | Setup URL example               | Base URL setting location in UI |
|-------------|----------------------------------|----------------------------------|
| qBittorrent | http://SERVER_IP:8080           | Not required                     |
| Jackett     | http://SERVER_IP:9117           | Settings → Server Configuration → Base URL |
| Radarr      | http://SERVER_IP:7878           | Settings → General → URL Base    |
| Sonarr      | http://SERVER_IP:8989           | Settings → General → URL Base    |
| Bazarr      | http://SERVER_IP:6767           | Settings → General → Base URL    |
| Ombi        | http://SERVER_IP:3579           | Settings → General → Base URL    |
| Plex        | http://SERVER_IP:32400/web      | Not required                     |
| Portainer   | http://SERVER_IP:9000           | Not required                     |

Setup tutorials (official or project docs):
- Plex setup wizard: `https://support.plex.tv/articles/200288896-basic-setup-wizard/`
- qBittorrent (LinuxServer image): `https://docs.linuxserver.io/images/docker-qbittorrent/`
- Jackett installation: `https://github.com/Jackett/Jackett`
- Radarr quick start: `https://wikiold.servarr.com/Radarr_Quick_Start_Guide`
- Sonarr installation: `https://wikiold.servarr.com/Sonarr_Installation`
- Bazarr setup guide: `https://wiki.bazarr.media/Getting-Started/Setup-Guide/`
- Ombi installation: `https://docs.ombi.app/guides/installation/`
- Portainer initial setup: `https://docs.portainer.io/start/install-ce/server/setup`

Disclaimer: These tutorials are created and owned by their respective organizations/authors. Full credit goes to them.

## Troubleshooting

- MEDIA_ROOT mount: ensure your media path is actually mounted.
  - `mount | grep "$MEDIA_ROOT"`
  - `ls -la "$MEDIA_ROOT"`
- Port conflicts: if preflight reports a busy port, stop the conflicting process or change the binding.
- Permissions (PUID/PGID): containers write as the user/group you set in `.env`.
  - `id -u` / `id -g`
  - `sudo chown -R $PUID:$PGID $CONFIG_ROOT`

## Ports and URLs

The table below lists direct ports and optional nginx path proxies. When
`configs/_templates/nginx/conf.d` exists, the installer copies templates into
`$CONFIG_ROOT/nginx/conf.d`, so path routing works immediately. After the first
install, edit the live configs under `$CONFIG_ROOT/nginx/conf.d`.

Example URLs (HTTP only):
- http://SERVER_IP/radarr
- http://SERVER_IP/sonarr
- http://SERVER_IP/qbit
- http://SERVER_IP/bazarr
- http://SERVER_IP/ombi
- http://SERVER_IP/portainer
- http://SERVER_IP/jackett
- http://SERVER_IP/plex

Plex uses `/plex` via `host.docker.internal:32400` because it runs in host
network mode. The nginx service adds an `extra_hosts` entry so the container can
reach the Docker host gateway.

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

## Disk usage endpoint

The disk usage API (`/api/disk`) runs `df` on the actual mount (recommended for Linux).
This works reliably with:

- USB disks
- FUSE
- mergerfs
- Plexdrive
- Docker bind mounts

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
