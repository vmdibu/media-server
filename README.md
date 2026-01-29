# Runtime Folder Contract (CONFIG_ROOT)

This document defines the canonical directory structure that must exist under
`CONFIG_ROOT` for the media server stack to run. These folders are created by
the install script and are never overwritten.

## Quick start

1) Clone the repo:

```bash
git clone <repo-url>
cd media-server
```

2) Create your environment file:

```bash
cp .env.example .env
```

3) Edit `.env` variables to match your host paths and user IDs.

4) Run the installer:

```bash
./scripts/install.sh
```

5) Check status:

```bash
docker compose ps
```

## Required folders and permissions

All containers use `PUID`/`PGID` from `.env` to map file ownership on the host.
Set these to your user ID and group ID:

```bash
id -u
id -g
```

Ensure the config directory is owned by that user/group:

```bash
sudo chown -R $PUID:$PGID $CONFIG_ROOT
```

`MEDIA_ROOT` must be a mounted filesystem, not an empty folder. Verify it:

```bash
mount | grep "$MEDIA_ROOT"
ls -la "$MEDIA_ROOT"
```

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
| Jackett     | 9117         | http://localhost:9117          | —          |
| Radarr      | 7878         | http://localhost:7878          | /radarr    |
| Sonarr      | 8989         | http://localhost:8989          | /sonarr    |
| Bazarr      | 6767         | http://localhost:6767          | /bazarr    |
| Ombi        | 3579         | http://localhost:3579          | /ombi      |
| Portainer   | 9000         | http://localhost:9000          | /portainer |
| Nginx       | 80/443       | http://localhost               | —          |

## Security notes

- Mounting `/var/run/docker.sock` (Portainer/Watchtower) grants admin control of Docker; keep access restricted.
- Plex uses host networking, which reduces container isolation; avoid exposing it beyond your LAN.
- Prefer firewall rules or LAN-only access for all service ports.

## Folder tree

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
