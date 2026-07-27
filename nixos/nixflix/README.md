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
| Bazarr      | API key        | `bazarr/api_key`          |

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
| qBittorrent | `http://qbittorrent.nixflix` | `http://localhost:8080` |
| Jellyfin    | `http://jellyfin.nixflix`    | `http://localhost:8096` |
| Seerr       | `http://seerr.nixflix`       | `http://localhost:5055` |
| Bazarr      | `http://bazarr.nixflix`      | `http://localhost:6767` |

## Automated integrations (Jellyfin Full Automation Guide 2026)

These one-shot systemd services run on first boot and on `nixflix refresh`
to wire the stack together per the
[Jellyfin Full Automation Guide (2026)][tutorial]:

| Service                           | What it does                                                     |
| --------------------------------- | ---------------------------------------------------------------- |
| `prowlarr-applications.service`   | Adds Sonarr/Radarr/Lidarr app entries in Prowlarr (fullSync)     |
| `prowlarr-indexers.service`       | Adds the indexers declared in `nixflix.prowlarr.config.indexers` |
| `radarr-jellyfin-connect.service` | Creates/updates the Jellyfin Connect notification in Radarr      |
| `sonarr-jellyfin-connect.service` | Creates/updates the Jellyfin Connect notification in Sonarr      |
| `bazarr-setup.service`            | Enables providers, score ≥ 90, sync, 3 AM scan                   |
| `seerr-setup.service`             | Initial Seerr setup: connect to Jellyfin, sync libraries         |
| `seerr-jellyfin.service`          | Maintain Seerr ↔ Jellyfin host settings                          |
| `seerr-radarr.service`            | Maintain Seerr → Radarr instance(s)                              |
| `seerr-sonarr.service`            | Maintain Seerr → Sonarr instance(s)                              |
| `recyclarr.service`               | Syncs TRaSH guide quality profiles to Radarr/Sonarr              |

`seerr-setup` and `prowlarr-indexers` are intentionally disabled at first boot
(intra-stack dependencies make them fail before everything is up). Run
`nixflix refresh` after the first successful `nixup` to apply them.

```bash
nixflix refresh     # re-run all config oneshots
nixflix check       # verify all services and integrations
```

### OpenSubtitles.com API key

`bazarr-setup` enables OpenSubtitles as a provider but cannot configure
credentials without a secret. Add the free API key via the Bazarr UI
(`Settings → Providers → OpenSubtitles.com`) — the provider slot is
already wired.

## Resources

- [Nixflix docs](https://kiriwalawren.github.io/nixflix/)
- [Nixflix GitHub](https://github.com/kiriwalawren/nixflix)
- [Basic setup example](https://kiriwalawren.github.io/nixflix/examples/basic-setup/)

[tutorial]: https://jellywatch.app/blog/jellyfin-full-automation-guide-radarr-sonarr-bazarr-jellyseerr-2026
