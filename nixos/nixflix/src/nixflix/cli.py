import os
import subprocess

import typer

app = typer.Typer()
STATE = "/data/.state"
SOPS_FILE = os.path.expanduser("~/dotfiles/secrets.yaml")
SERVICES = [
    "postgresql",
    "nginx",
    "sonarr",
    "radarr",
    "lidarr",
    "prowlarr",
    "sabnzbd",
    "jellyfin",
    "seerr",
]


def run(cmd: str):
    subprocess.run(cmd, shell=True, check=False)


@app.command()
def restart():
    """Restart all nixflix services"""
    for svc in SERVICES:
        print(f"Restarting {svc}...")
        run(f"sudo systemctl restart {svc}.service 2>/dev/null || true")
    print("Done.")


CONFIG_SERVICES = [
    "sonarr-config",
    "sonarr-setup-logs-db",
    "radarr-config",
    "radarr-setup-logs-db",
    "lidarr-config",
    "lidarr-setup-logs-db",
    "prowlarr-config",
    "prowlarr-setup-logs-db",
    "prowlarr-tags",
    "jellyfin-setup-wizard",
    "seerr-env",
]


@app.command()
def refresh():
    """Re-run config oneshot services (needed after nixflix clean + nixup)"""
    print("Restarting config services...")
    for svc in CONFIG_SERVICES:
        run(f"sudo systemctl restart {svc}.service 2>/dev/null || true")
    print("Done.")


@app.command()
def clean():
    """Wipe all state data and recreate dirs"""
    print("Stopping all services...")
    for svc in SERVICES:
        run(f"sudo systemctl stop {svc}.service 2>/dev/null || true")
    print("Removing all state data...")
    run(f"sudo rm -rf {STATE}/{{jellyfin,sonarr,radarr,lidarr,prowlarr,seerr}}")
    setup_dirs_impl()
    print("Done. Run: nixflix full-refresh")


@app.command()
def full_refresh():
    """Clean state, rebuild system, re-apply config — all in one"""
    print("=== Step 1: Clean state ===")
    for svc in SERVICES:
        run(f"sudo systemctl stop {svc}.service 2>/dev/null || true")
    run(f"sudo rm -rf {STATE}/{{jellyfin,sonarr,radarr,lidarr,prowlarr,seerr}}")
    setup_dirs_impl()

    print("\n=== Step 2: Rebuild system ===")
    log = subprocess.run(
        "sudo nixos-rebuild switch --quiet", capture_output=True, text=True, shell=True
    )
    if log.returncode != 0:
        print(log.stdout + log.stderr)
        raise SystemExit(1)

    log = subprocess.run(
        "nix run home-manager -- init --switch ~/dotfiles",
        capture_output=True,
        text=True,
        shell=True,
    )
    if log.returncode != 0:
        print(log.stdout + log.stderr)
        raise SystemExit(1)

    print("\n=== Step 3: Re-apply config services ===")
    for svc in CONFIG_SERVICES:
        run(f"sudo systemctl restart {svc}.service 2>/dev/null || true")

    print("\nDone.")


@app.command()
def setup():
    """Recreate jellyfin directories"""
    setup_dirs_impl()
    print("Done. Run: nixup")


@app.command()
def secrets(action: str = typer.Argument("edit", help="edit or show")):
    """Manage encrypted secrets"""
    if action == "edit":
        run(f"sops {SOPS_FILE}")
    elif action == "show":
        run(f"sops --decrypt {SOPS_FILE}")
    else:
        print("Usage: nixflix secrets {edit|show}")


def setup_dirs_impl():
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


def main():
    app()


if __name__ == "__main__":
    main()
