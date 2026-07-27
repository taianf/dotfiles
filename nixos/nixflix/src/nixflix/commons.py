import os
import subprocess

STATE = "/data/.state"
SOPS_FILE = os.path.expanduser("~/dotfiles/secrets.yaml")
SERVICES = [
    "postgresql",
    "nginx",
    "sonarr",
    "radarr",
    "lidarr",
    "prowlarr",
    "qbittorrent",
    "jellyfin",
    "seerr",
    "bazarr",
    "recyclarr",
]
CONFIG_SERVICES = [
    "sonarr-config",
    "sonarr-setup-logs-db",
    "sonarr-jellyfin-connect",
    "radarr-config",
    "radarr-setup-logs-db",
    "radarr-jellyfin-connect",
    "lidarr-config",
    "lidarr-setup-logs-db",
    "prowlarr-config",
    "prowlarr-setup-logs-db",
    "prowlarr-tags",
    "jellyfin-api-key",
    "jellyfin-setup-wizard",
    "jellyfin-metadata-config",
    "jellyfin-system-config",
    "seerr-env",
    "bazarr-setup",
]


def run(cmd: str):
    subprocess.run(cmd, shell=True, check=False)


def setup_dirs():
    print("Creating state directories...")
    dirs = {
        "jellyfin": ("jellyfin", "media", "{config,cache,log,data}"),
        "sonarr": ("sonarr", "media", ""),
        "radarr": ("radarr", "media", ""),
        "lidarr": ("lidarr", "media", ""),
        "prowlarr": ("prowlarr", "prowlarr", ""),
        "seerr": ("seerr", "seerr", ""),
    }
    for name, (user, group, subdirs) in dirs.items():
        path = f"{STATE}/{name}"
        if subdirs:
            run(f"sudo mkdir -p {path}/{subdirs}")
            run(f"sudo chown -R {user}:{group} {path}")
        else:
            run(f"sudo mkdir -p {path}")
            run(f"sudo chown {user}:{group} {path}")
    print("Done.")
