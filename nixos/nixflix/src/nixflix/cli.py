import json
import os
import subprocess
import sys
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import Optional
from urllib.error import HTTPError
from urllib.error import URLError
from urllib.request import Request
from urllib.request import urlopen

import typer

app = typer.Typer()
STATE = "/data/.state"
SOPS_FILE = os.path.expanduser("~/dotfiles/secrets.yaml")
SECRETS_DIR = "/run/secrets"
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
]


def run(cmd: str):
    subprocess.run(cmd, shell=True, check=False)


# ── Health check ──────────────────────────────────────────────────


@dataclass
class _Check:
    name: str
    passed: bool = False
    detail: str = ""
    children: list["_Check"] = field(default_factory=list)


def _read_secret(path: str) -> Optional[str]:
    full = os.path.join(SECRETS_DIR, path)
    try:
        with open(full) as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError, OSError):
        return None


def _sudo_secret(path: str) -> Optional[str]:
    try:
        r = subprocess.run(
            ["sudo", "-n", "cat", os.path.join(SECRETS_DIR, path)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        pass
    return None


def _secret(path: str) -> Optional[str]:
    return _read_secret(path) or _sudo_secret(path)


def _api_get(url: str, headers: dict | None = None):
    req = Request(url, headers=headers or {}, method="GET")
    try:
        with urlopen(req, timeout=10) as resp:
            body = resp.read().decode()
            try:
                return resp.status, json.loads(body), None
            except json.JSONDecodeError:
                return resp.status, None, body
    except HTTPError as e:
        return e.code, None, (e.read().decode() if e.fp else "")
    except (URLError, OSError) as e:
        return -1, None, str(e.reason) if hasattr(e, "reason") else str(e)


def _systemd_active(unit: str) -> bool:
    r = subprocess.run(
        ["systemctl", "is-active", f"{unit}.service"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return r.stdout.strip() == "active"


def _flatten(checks: list[_Check]):
    for c in checks:
        yield c
        yield from _flatten(c.children)


def _print_check(c: _Check, level: int):
    indent = "  " * level
    icon = "✓" if c.passed else "✗"
    if c.children:
        print(f"{indent}{icon} {c.name}")
        if c.detail:
            print(f"{indent}    → {c.detail}")
        for child in c.children:
            _print_check(child, level + 1)
    else:
        detail = f" — {c.detail}" if c.detail else ""
        print(f"{indent}  {icon} {c.name}{detail}")


def _run_checks():
    results: list[_Check] = []

    def add(name: str) -> _Check:
        c = _Check(name)
        results.append(c)
        return c

    # ── Services running ──
    c = add("All services running")
    ok = True
    for svc in SERVICES:
        active = _systemd_active(svc)
        child = _Check(svc, passed=active, detail="" if active else "not running")
        if not active:
            ok = False
        c.children.append(child)
    c.ok() if ok else c.fail("some services are not running")

    # ── Service APIs ──
    api_checks = [
        (
            "Sonarr API",
            "http://127.0.0.1:8989/api/v3/system/status",
            {"X-Api-Key": _secret("sonarr/api_key") or ""},
        ),
        (
            "Radarr API",
            "http://127.0.0.1:7878/api/v3/system/status",
            {"X-Api-Key": _secret("radarr/api_key") or ""},
        ),
        (
            "Lidarr API",
            "http://127.0.0.1:8686/api/v1/system/status",
            {"X-Api-Key": _secret("lidarr/api_key") or ""},
        ),
        (
            "Prowlarr API",
            "http://127.0.0.1:9696/api/v1/system/status",
            {"X-Api-Key": _secret("prowlarr/api_key") or ""},
        ),
        ("Jellyfin API", "http://127.0.0.1:8096/system/info/public", {}),
        (
            "Seerr API",
            "http://127.0.0.1:5055/api/v1/status",
            {"X-Api-Key": _secret("seerr/api_key") or ""},
        ),
        (
            "Jellyfin auth",
            "http://127.0.0.1:8096/system/info",
            {"X-Emby-Token": _secret("jellyfin/api_key") or ""},
        ),
    ]
    c = add("Service APIs accessible")
    ok = True
    for name, url, headers in api_checks:
        status, data, err = _api_get(url, headers)
        child = _Check(name)
        if status in (200, 204):
            child.ok(f"HTTP {status}")
        else:
            child.fail(f"HTTP {status}: {err or 'no response'}")
            ok = False
        c.children.append(child)
    c.ok() if ok else c.fail("some APIs are not accessible")

    # ── Cross-service integration ──
    c = add("Service-to-service integration")
    radarr_key = _secret("radarr/api_key") or ""
    sonarr_key = _secret("sonarr/api_key") or ""

    sd_status, sd_data, sd_err = _api_get(
        "http://127.0.0.1:7878/api/v3/downloadclient",
        {"X-Api-Key": radarr_key},
    )
    sd_child = _Check("Radarr → qBittorrent download client")
    if sd_data:
        clients = [dc for dc in sd_data if "qbittorrent" in json.dumps(dc).lower()]
        if clients:
            sd_child.ok(f"found {len(clients)} qBittorrent client(s)")
        else:
            sd_child.fail("no qBittorrent download client configured")
    else:
        sd_child.fail(f"HTTP {sd_status}: {sd_err}")
    c.children.append(sd_child)

    ss_status, ss_data, ss_err = _api_get(
        "http://127.0.0.1:8989/api/v3/downloadclient",
        {"X-Api-Key": sonarr_key},
    )
    ss_child = _Check("Sonarr → qBittorrent download client")
    if ss_data:
        clients = [dc for dc in ss_data if "qbittorrent" in json.dumps(dc).lower()]
        if clients:
            ss_child.ok(f"found {len(clients)} qBittorrent client(s)")
        else:
            ss_child.fail("no qBittorrent download client configured")
    else:
        ss_child.fail(f"HTTP {ss_status}: {ss_err}")
    c.children.append(ss_child)

    prowlarr_key = _secret("prowlarr/api_key") or ""
    pa_status, pa_data, pa_err = _api_get(
        "http://127.0.0.1:9696/api/v1/applications",
        {"X-Api-Key": prowlarr_key},
    )

    pa_sonarr = _Check("Prowlarr → Sonarr app sync")
    if pa_data:
        apps = [a for a in pa_data if "sonarr" in json.dumps(a).lower()]
        if apps:
            synced = all(a.get("syncLevel") == "fullSync" for a in apps)
            pa_sonarr.ok(
                f"{len(apps)} Sonarr app(s) synced"
            ) if synced else pa_sonarr.fail("not full sync")
        else:
            pa_sonarr.fail("no Sonarr application configured")
    else:
        pa_sonarr.fail(f"HTTP {pa_status}: {pa_err}")
    c.children.append(pa_sonarr)

    pa_radarr = _Check("Prowlarr → Radarr app sync")
    if pa_data:
        apps = [a for a in pa_data if "radarr" in json.dumps(a).lower()]
        if apps:
            synced = all(a.get("syncLevel") == "fullSync" for a in apps)
            pa_radarr.ok(
                f"{len(apps)} Radarr app(s) synced"
            ) if synced else pa_radarr.fail("not full sync")
        else:
            pa_radarr.fail("no Radarr application configured")
    else:
        pa_radarr.fail(f"HTTP {pa_status}: {pa_err}")
    c.children.append(pa_radarr)

    bazarr_key = _secret("bazarr/api_key") or ""
    bz_status, bz_data, bz_err = _api_get(
        "http://127.0.0.1:6767/api/system/settings",
        {"X-Api-Key": bazarr_key},
    )

    bz_s = _Check("Bazarr → Sonarr connection")
    if bz_data:
        bz_s.ok("Sonarr integration enabled") if bz_data.get("general", {}).get(
            "use_sonarr"
        ) else bz_s.fail("not enabled")
    else:
        bz_s.fail(f"HTTP {bz_status}: {bz_err}")
    c.children.append(bz_s)

    bz_r = _Check("Bazarr → Radarr connection")
    if bz_data:
        bz_r.ok("Radarr integration enabled") if bz_data.get("general", {}).get(
            "use_radarr"
        ) else bz_r.fail("not enabled")
    else:
        bz_r.fail("could not read Bazarr settings")
    c.children.append(bz_r)

    seerr_key = _secret("seerr/api_key") or ""
    sj_status, sj_data, sj_err = _api_get(
        "http://127.0.0.1:5055/api/v1/settings/jellyfin",
        {"X-Api-Key": seerr_key},
    )
    sj = _Check("Seerr → Jellyfin connection")
    if sj_data:
        sj.ok(f"at {sj_data['hostname']}:{sj_data.get('port', 8096)}") if sj_data.get(
            "hostname"
        ) else sj.fail("not configured")
    else:
        sj.fail(f"HTTP {sj_status}: {sj_err}")
    c.children.append(sj)

    for label, path in [("Seerr → Radarr", "radarr"), ("Seerr → Sonarr", "sonarr")]:
        st, dt, er = _api_get(
            f"http://127.0.0.1:5055/api/v1/settings/{path}",
            {"X-Api-Key": seerr_key},
        )
        child = _Check(label)
        if dt:
            items = dt if isinstance(dt, list) else [dt]
            if any(s.get("isDefault") for s in items):
                child.ok("configured as default")
            else:
                child.fail("no default configured")
        else:
            child.fail(f"HTTP {st}: {er}")
        c.children.append(child)

    c.ok() if all(x.passed for x in c.children) else c.fail(
        "some integrations are missing"
    )

    # ── Prowlarr indexers ──
    c = add("Prowlarr indexers configured")
    pi_status, pi_data, pi_err = _api_get(
        "http://127.0.0.1:9696/api/v1/indexer",
        {"X-Api-Key": prowlarr_key},
    )
    if pi_data:
        enabled = [i for i in pi_data if i.get("enable")]
        c.ok(f"{len(enabled)} indexer(s) enabled") if enabled else c.fail(
            "no indexers enabled"
        )
    else:
        c.fail(f"HTTP {pi_status}: {pi_err}")

    # ── Radarr & Sonarr config ──
    c = add("Radarr & Sonarr configuration")

    rrf = _Check("Radarr root folder configured")
    st, dt, er = _api_get(
        "http://127.0.0.1:7878/api/v3/rootfolder", {"X-Api-Key": radarr_key}
    )
    if dt and len(dt) > 0:
        rrf.ok(f"path: {dt[0].get('path', 'unknown')}")
    else:
        rrf.fail("no root folder" if dt else f"HTTP {st}: {er}")
    c.children.append(rrf)

    rrn = _Check("Radarr rename movies enabled")
    st, dt, er = _api_get(
        "http://127.0.0.1:7878/api/v3/config/naming", {"X-Api-Key": radarr_key}
    )
    if dt:
        rrn.ok() if dt.get("renameEpisodes") else rrn.fail("not enabled")
    else:
        rrn.fail(f"HTTP {st}: {er}")
    c.children.append(rrn)

    rjf = _Check("Radarr → Jellyfin notification")
    st, dt, er = _api_get(
        "http://127.0.0.1:7878/api/v3/notification", {"X-Api-Key": radarr_key}
    )
    if dt:
        jf = [n for n in dt if "jellyfin" in json.dumps(n).lower()]
        rjf.ok(f"{len(jf)} Jellyfin notification(s)") if jf else rjf.fail(
            "no Jellyfin notification"
        )
    else:
        rjf.fail(f"HTTP {st}: {er}")
    c.children.append(rjf)

    srf = _Check("Sonarr root folder configured")
    st, dt, er = _api_get(
        "http://127.0.0.1:8989/api/v3/rootfolder", {"X-Api-Key": sonarr_key}
    )
    if dt and len(dt) > 0:
        srf.ok(f"path: {dt[0].get('path', 'unknown')}")
    else:
        srf.fail("no root folder" if dt else f"HTTP {st}: {er}")
    c.children.append(srf)

    srn = _Check("Sonarr rename episodes enabled")
    st, dt, er = _api_get(
        "http://127.0.0.1:8989/api/v3/config/naming", {"X-Api-Key": sonarr_key}
    )
    if dt:
        srn.ok() if dt.get("renameEpisodes") else srn.fail("not enabled")
    else:
        srn.fail(f"HTTP {st}: {er}")
    c.children.append(srn)

    sjf = _Check("Sonarr → Jellyfin notification")
    st, dt, er = _api_get(
        "http://127.0.0.1:8989/api/v3/notification", {"X-Api-Key": sonarr_key}
    )
    if dt:
        jf = [n for n in dt if "jellyfin" in json.dumps(n).lower()]
        sjf.ok(f"{len(jf)} Jellyfin notification(s)") if jf else sjf.fail(
            "no Jellyfin notification"
        )
    else:
        sjf.fail(f"HTTP {st}: {er}")
    c.children.append(sjf)

    c.ok() if all(x.passed for x in c.children) else c.fail(
        "some Radarr/Sonarr config items are missing"
    )

    # ── Bazarr config ──
    c = add("Bazarr configuration")
    bc_status, bc_data, bc_err = _api_get(
        "http://127.0.0.1:6767/api/system/settings",
        {"X-Api-Key": bazarr_key},
    )
    if not bc_data:
        c.fail(f"cannot reach Bazarr API: HTTP {bc_status} {bc_err}")
    else:
        bl = _Check("Bazarr languages configured")
        st, dt, er = _api_get(
            "http://127.0.0.1:6767/api/system/languages", {"X-Api-Key": bazarr_key}
        )
        if dt:
            enabled = [l for l in dt if l.get("enabled")]
            bl.ok(
                f"enabled: {', '.join(l.get('code2', '?') for l in enabled)}"
            ) if enabled else bl.fail("no languages enabled")
        else:
            bl.fail(f"HTTP {st}: {er}")
        c.children.append(bl)

        bp = _Check("Bazarr language profiles created")
        st, dt, er = _api_get(
            "http://127.0.0.1:6767/api/system/languages/profiles",
            {"X-Api-Key": bazarr_key},
        )
        if dt and len(dt) > 0:
            bp.ok(f"profiles: {', '.join(p.get('name', '?') for p in dt)}")
        else:
            bp.fail("no profiles" if dt else f"HTTP {st}: {er}")
        c.children.append(bp)

        bpr = _Check("Bazarr subtitle providers configured")
        providers = bc_data.get("general", {}).get("enabled_providers", [])
        bpr.ok(f"{len(providers)} provider(s) enabled") if providers else bpr.fail(
            "no providers enabled"
        )
        c.children.append(bpr)

        c.ok() if all(x.passed for x in c.children) else c.fail(
            "some Bazarr config items are missing"
        )

    # ── Report ──
    passed = sum(1 for c in _flatten(results) if c.passed)
    total = sum(1 for _ in _flatten(results))
    print()
    print("=" * 60)
    print("  Nixflix Health Check")
    print("=" * 60)
    print()
    for rc in results:
        _print_check(rc, 0)
    print()
    print("=" * 60)
    if passed == total:
        print(f"  ✓ {passed}/{total} checks passed — all good!")
    else:
        print(f"  ✗ {passed}/{total} checks passed — {total - passed} failure(s)")
    print("=" * 60)
    return 0 if passed == total else 1


# ── CLI commands ──────────────────────────────────────────────────


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
    "jellyfin-api-key",
    "jellyfin-setup-wizard",
    "jellyfin-metadata-config",
    "jellyfin-system-config",
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
    _setup_dirs()
    print("Done. Run: nixflix full-refresh")


@app.command()
def full_refresh():
    """Clean state, rebuild system, re-apply config — all in one"""
    print("=== Step 1: Clean state ===")
    for svc in SERVICES:
        run(f"sudo systemctl stop {svc}.service 2>/dev/null || true")
    run(f"sudo rm -rf {STATE}/{{jellyfin,sonarr,radarr,lidarr,prowlarr,seerr}}")
    _setup_dirs()

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
    _setup_dirs()
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
    sys.exit(_run_checks())


def _setup_dirs():
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
