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


@app.command()
def clean():
    """Wipe all state data and recreate dirs"""
    print("Stopping all services...")
    for svc in SERVICES:
        run(f"sudo systemctl stop {svc}.service 2>/dev/null || true")
    print("Removing all state data...")
    run(f"sudo rm -rf {STATE}/{{jellyfin,sonarr,radarr,lidarr,prowlarr,seerr}}")
    setup_dirs_impl()
    print("Done. Run: nixup")


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
    print("Creating jellyfin directories...")
    run(f"sudo mkdir -p {STATE}/jellyfin/{{config,cache,log,data}}")
    run(f"sudo chown -R jellyfin:media {STATE}/jellyfin")
    print("Done.")


def main():
    app()


if __name__ == "__main__":
    main()
