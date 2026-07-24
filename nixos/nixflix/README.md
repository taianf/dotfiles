# Nixflix Setup

Media server stack: Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent, Jellyfin, Seerr.

## Secrets

All API keys and passwords are managed via **sops-nix** and stored encrypted in `../../secrets.yaml`.

### Required secrets

| Service     | Key            | Path in secrets.yaml      |
| ----------- | -------------- | ------------------------- |
| Sonarr      | API key        | `sonarr/api_key`          |
| Sonarr      | Password       | `sonarr/password`         |
| Radarr      | API key        | `radarr/api_key`          |
| Radarr      | Password       | `radarr/password`         |
| Lidarr      | API key        | `lidarr/api_key`          |
| Lidarr      | Password       | `lidarr/password`         |
| Prowlarr    | API key        | `prowlarr/api_key`        |
| Prowlarr    | Password       | `prowlarr/password`       |
| qBittorrent | Password       | `qbittorrent/password`    |
| Jellyfin    | API key        | `jellyfin/api_key`        |
| Jellyfin    | Admin password | `jellyfin/admin_password` |
| Seerr       | API key        | `seerr/api_key`           |

### Editing secrets

```bash
# Open encrypted secrets file (decrypts on load, re-encrypts on save)
sops ~/dotfiles/secrets.yaml
```

### Adding a new machine

Each machine decrypts secrets using its SSH host key. To add a new machine:

```bash
# On the new machine, ensure SSH host key exists
sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# Get the age public key
nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'

# Add the new key to .sops.yaml
# Then re-encrypt secrets with all keys
sops updatekeys ~/dotfiles/secrets.yaml
```

## Directory structure

Created automatically on first rebuild:

```text
/data/
├── media/
│   ├── movies/       # Radarr → Jellyfin "Movies"
│   ├── tv/           # Sonarr → Jellyfin "Shows"
│   ├── music/        # Lidarr → Jellyfin "Music"
│   └── anime/        # Sonarr Anime → Jellyfin "Shows"
├── downloads/        # qBittorrent downloads
└── .state/           # Service state ( databases, configs )
```

## Service access

| Service     | Reverse proxy                | Direct                  |
| ----------- | ---------------------------- | ----------------------- |
| Sonarr      | `http://sonarr.nixflix`      | `http://localhost:8989` |
| Radarr      | `http://radarr.nixflix`      | `http://localhost:7878` |
| Lidarr      | `http://lidarr.nixflix`      | `http://localhost:8686` |
| Prowlarr    | `http://prowlarr.nixflix`    | `http://localhost:9696` |
| qBittorrent | `http://qbittorrent.nixflix` | `http://localhost:8282` |
| Jellyfin    | `http://jellyfin.nixflix`    | `http://localhost:8096` |
| Seerr       | `http://seerr.nixflix`       | `http://localhost:5055` |

## Resources

- [Nixflix docs](https://kiriwalawren.github.io/nixflix/)
- [Nixflix GitHub](https://github.com/kiriwalawren/nixflix)
- [Basic setup example](https://kiriwalawren.github.io/nixflix/examples/basic-setup/)
