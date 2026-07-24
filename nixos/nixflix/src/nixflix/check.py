import json
import os
import subprocess
from dataclasses import dataclass
from dataclasses import field
from urllib.error import HTTPError
from urllib.error import URLError
from urllib.request import Request
from urllib.request import urlopen

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


@dataclass
class _Check:
    name: str
    passed: bool = False
    detail: str = ""
    children: list["_Check"] = field(default_factory=list)

    def fail(self, detail: str = ""):
        self.passed = False
        self.detail = detail
        return self

    def ok(self, detail: str = ""):
        self.passed = True
        self.detail = detail
        return self


def _read_secret(path: str) -> str | None:
    full = os.path.join(SECRETS_DIR, path)
    try:
        with open(full) as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError, OSError):
        return None


def _sudo_secret(path: str) -> str | None:
    try:
        r = subprocess.run(
            ["sudo", "-n", "cat", os.path.join(SECRETS_DIR, path)],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        pass
    return None


def _secret(path: str) -> str | None:
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
        check=False,
    )
    return r.stdout.strip() == "active"


def _check_services_running():
    c = _Check("All services running")
    all_ok = True
    for svc in SERVICES:
        active = _systemd_active(svc)
        child = _Check(svc, passed=active, detail="" if active else "not running")
        if not active:
            all_ok = False
        c.children.append(child)
    c.ok() if all_ok else c.fail("some services are not running")
    return c


def _check_service_apis():
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
    c = _Check("Service APIs accessible")
    all_ok = True
    for name, url, headers in api_checks:
        status, _, err = _api_get(url, headers)
        child = _Check(name)
        if status in (200, 204):
            child.ok(f"HTTP {status}")
        else:
            child.fail(f"HTTP {status}: {err or 'no response'}")
            all_ok = False
        c.children.append(child)
    c.ok() if all_ok else c.fail("some APIs are not accessible")
    return c


def _check_cross_service_integration():  # noqa: PLR0912
    c = _Check("Service-to-service integration")
    radarr_key = _secret("radarr/api_key") or ""
    sonarr_key = _secret("sonarr/api_key") or ""
    prowlarr_key = _secret("prowlarr/api_key") or ""
    bazarr_key = _secret("bazarr/api_key") or ""
    seerr_key = _secret("seerr/api_key") or ""

    for label, url, key_field in [
        (
            "Radarr → qBittorrent download client",
            "http://127.0.0.1:7878/api/v3/downloadclient",
            radarr_key,
        ),
        (
            "Sonarr → qBittorrent download client",
            "http://127.0.0.1:8989/api/v3/downloadclient",
            sonarr_key,
        ),
    ]:
        st, dt, er = _api_get(url, {"X-Api-Key": key_field})
        child = _Check(label)
        if dt:
            clients = [dc for dc in dt if "qbittorrent" in json.dumps(dc).lower()]
            child.ok(
                f"found {len(clients)} qBittorrent client(s)"
            ) if clients else child.fail("no qBittorrent download client configured")
        else:
            child.fail(f"HTTP {st}: {er}")
        c.children.append(child)

    pa_status, pa_data, pa_err = _api_get(
        "http://127.0.0.1:9696/api/v1/applications",
        {"X-Api-Key": prowlarr_key},
    )

    for label, service in [
        ("Prowlarr → Sonarr app sync", "sonarr"),
        ("Prowlarr → Radarr app sync", "radarr"),
    ]:
        child = _Check(label)
        if pa_data:
            apps = [a for a in pa_data if service in json.dumps(a).lower()]
            if apps:
                synced = all(a.get("syncLevel") == "fullSync" for a in apps)
                child.ok(
                    f"{len(apps)} {service} app(s) synced"
                ) if synced else child.fail("not full sync")
            else:
                child.fail(f"no {service} application configured")
        else:
            child.fail(f"HTTP {pa_status}: {pa_err}")
        c.children.append(child)

    bz_status, bz_data, bz_err = _api_get(
        "http://127.0.0.1:6767/api/system/settings",
        {"X-Api-Key": bazarr_key},
    )

    for label, setting in [
        ("Bazarr → Sonarr connection", "use_sonarr"),
        ("Bazarr → Radarr connection", "use_radarr"),
    ]:
        child = _Check(label)
        if bz_data:
            enabled = bz_data.get("general", {}).get(setting, False)
            child.ok(f"{setting} enabled") if enabled else child.fail(
                f"{setting} not enabled"
            )
        else:
            child.fail(
                f"HTTP {bz_status}: {bz_err}"
                if label == "Bazarr → Sonarr connection"
                else "could not read Bazarr settings"
            )
        c.children.append(child)

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
            child.ok("configured as default") if any(
                s.get("isDefault") for s in items
            ) else child.fail("no default configured")
        else:
            child.fail(f"HTTP {st}: {er}")
        c.children.append(child)

    c.ok() if all(x.passed for x in c.children) else c.fail(
        "some integrations are missing"
    )
    return c


def _check_prowlarr_indexers():
    c = _Check("Prowlarr indexers configured")
    prowlarr_key = _secret("prowlarr/api_key") or ""
    st, dt, er = _api_get(
        "http://127.0.0.1:9696/api/v1/indexer",
        {"X-Api-Key": prowlarr_key},
    )
    if dt:
        enabled = [i for i in dt if i.get("enable")]
        c.ok(f"{len(enabled)} indexer(s) enabled") if enabled else c.fail(
            "no indexers enabled"
        )
    else:
        c.fail(f"HTTP {st}: {er}")
    return c


def _check_radarr_sonarr_config():
    c = _Check("Radarr & Sonarr configuration")
    radarr_key = _secret("radarr/api_key") or ""
    sonarr_key = _secret("sonarr/api_key") or ""

    checks = [
        (
            "Radarr root folder configured",
            "http://127.0.0.1:7878/api/v3/rootfolder",
            radarr_key,
            None,
        ),
        (
            "Radarr rename movies enabled",
            "http://127.0.0.1:7878/api/v3/config/naming",
            radarr_key,
            "renameEpisodes",
        ),
        (
            "Radarr → Jellyfin notification",
            "http://127.0.0.1:7878/api/v3/notification",
            radarr_key,
            "jellyfin",
        ),
        (
            "Sonarr root folder configured",
            "http://127.0.0.1:8989/api/v3/rootfolder",
            sonarr_key,
            None,
        ),
        (
            "Sonarr rename episodes enabled",
            "http://127.0.0.1:8989/api/v3/config/naming",
            sonarr_key,
            "renameEpisodes",
        ),
        (
            "Sonarr → Jellyfin notification",
            "http://127.0.0.1:8989/api/v3/notification",
            sonarr_key,
            "jellyfin",
        ),
    ]

    for label, url, key, check in checks:
        st, dt, er = _api_get(url, {"X-Api-Key": key})
        child = _Check(label)
        if check is None:
            if dt and len(dt) > 0:
                child.ok(f"path: {dt[0].get('path', 'unknown')}")
            else:
                child.fail("no root folder" if dt else f"HTTP {st}: {er}")
        elif check == "renameEpisodes":
            if dt:
                child.ok() if dt.get("renameEpisodes") else child.fail("not enabled")
            else:
                child.fail(f"HTTP {st}: {er}")
        elif dt:
            matches = [n for n in dt if check in json.dumps(n).lower()]
            child.ok(
                f"{len(matches)} {check} notification(s)"
            ) if matches else child.fail(f"no {check} notification")
        else:
            child.fail(f"HTTP {st}: {er}")
        c.children.append(child)

    c.ok() if all(x.passed for x in c.children) else c.fail(
        "some Radarr/Sonarr config items are missing"
    )
    return c


def _check_bazarr_config():
    c = _Check("Bazarr configuration")
    bazarr_key = _secret("bazarr/api_key") or ""

    bc_status, bc_data, bc_err = _api_get(
        "http://127.0.0.1:6767/api/system/settings",
        {"X-Api-Key": bazarr_key},
    )
    if not bc_data:
        c.fail(f"cannot reach Bazarr API: HTTP {bc_status} {bc_err}")
        return c

    bl = _Check("Bazarr languages configured")
    st, dt, er = _api_get(
        "http://127.0.0.1:6767/api/system/languages",
        {"X-Api-Key": bazarr_key},
    )
    if dt:
        enabled = [lang for lang in dt if lang.get("enabled")]
        bl.ok(
            f"enabled: {', '.join(lang.get('code2', '?') for lang in enabled)}"
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
    return c


def _flatten(checks: list[_Check]):
    for chk in checks:
        yield chk
        yield from _flatten(chk.children)


def _print_report(results: list[_Check]) -> int:
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


def run_checks() -> int:
    results = [
        _check_services_running(),
        _check_service_apis(),
        _check_cross_service_integration(),
        _check_prowlarr_indexers(),
        _check_radarr_sonarr_config(),
        _check_bazarr_config(),
    ]
    return _print_report(results)
