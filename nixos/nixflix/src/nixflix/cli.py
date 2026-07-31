import subprocess
import sys

import typer

from .check import run_checks
from .commons import CONFIG_SERVICES
from .commons import SERVICES
from .commons import SOPS_FILE
from .commons import STATE
from .commons import run
from .commons import setup_dirs

app = typer.Typer()


@app.command()
def restart():
    """Restart all nixflix services"""
    for svc in SERVICES:
        print(f"Restarting {svc}...")
        run(f"sudo systemctl restart {svc}.service 2>/dev/null || true")
    print("Done.")


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
    run(f"sudo rm -rf {STATE}/{{jellyfin,sonarr,radarr,lidarr,prowlarr,seerr,bazarr}}")
    setup_dirs()
    print("Done. Run: nixflix full-refresh")


@app.command()
def full_refresh():
    """Clean state, rebuild system, re-apply config — all in one"""
    print("=== Step 1: Clean state ===")
    for svc in SERVICES:
        run(f"sudo systemctl stop {svc}.service 2>/dev/null || true")
    run(f"sudo rm -rf {STATE}/{{jellyfin,sonarr,radarr,lidarr,prowlarr,seerr,bazarr}}")
    setup_dirs()

    print("\n=== Step 2: Reset oneshot services (force re-run after state wipe) ===")
    for svc in CONFIG_SERVICES:
        run(f"sudo systemctl stop {svc}.service 2>/dev/null || true")
        run(f"sudo systemctl reset-failed {svc}.service 2>/dev/null || true")

    print("\n=== Step 3: Rebuild system ===")
    log = subprocess.run(
        "nixup",
        capture_output=True,
        text=True,
        shell=True,
        check=False,
    )
    if log.returncode != 0:
        print(log.stdout + log.stderr)
        raise SystemExit(1)

    print("\n=== Step 4: Re-apply config services ===")
    for svc in CONFIG_SERVICES:
        run(f"sudo systemctl restart {svc}.service 2>/dev/null || true")
    print("\nDone.")


@app.command()
def setup():
    """Recreate jellyfin directories"""
    setup_dirs()
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


@app.command()
def check():
    """Check all services health, API connectivity, and cross-service integration"""
    sys.exit(run_checks())


def main():
    app()


if __name__ == "__main__":
    main()
