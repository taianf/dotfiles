import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from dataclasses import field
from typing import Optional
from urllib.error import HTTPError
from urllib.error import URLError
from urllib.request import Request
from urllib.request import urlopen

SECRETS_DIR = "/run/secrets"


@dataclass
class Check:
    name: str
    passed: bool = False
    detail: str = ""
    children: list["Check"] = field(default_factory=list)

    def fail(self, detail: str = ""):
        self.passed = False
        self.detail = detail
        return self

    def ok(self, detail: str = ""):
        self.passed = True
        self.detail = detail
        return self


def read_secret(path: str) -> Optional[str]:
    full = os.path.join(SECRETS_DIR, path)
    try:
        with open(full) as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError, OSError):
        return None


def sudo_read_secret(path: str) -> Optional[str]:
    full = os.path.join(SECRETS_DIR, path)
    try:
        r = subprocess.run(
            ["sudo", "-n", "cat", full],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        pass
    return None


def get_secret(path: str) -> Optional[str]:
    v = read_secret(path)
    if v is not None:
        return v
    return sudo_read_secret(path)


def api_get(
    url: str, headers: dict = None
) -> tuple[int, Optional[dict], Optional[str]]:
    req = Request(url, headers=headers or {}, method="GET")
    try:
        with urlopen(req, timeout=10) as resp:
            body = resp.read().decode()
            try:
                return resp.status, json.loads(body), None
            except json.JSONDecodeError:
                return resp.status, None, body
    except HTTPError as e:
        body = e.read().decode() if e.fp else ""
        return e.code, None, body
    except URLError as e:
        return -1, None, str(e.reason)
    except OSError as e:
        return -1, None, str(e)


class NixflixChecker:
    def __init__(self):
        self.results: list[Check] = []

    def check(self, name: str) -> Check:
        c = Check(name)
        self.results.append(c)
        return c

    def run_all(self):
        self._check_services_running()
        self._check_service_apis()
        self._check_cross_service_integration()
        self._check_prowlarr_indexers()
        self._check_radarr_sonarr_config()
        self._check_bazarr_config()
        self._print_report()

    def _systemd_active(self, unit: str) -> bool:
        r = subprocess.run(
            ["systemctl", "is-active", f"{unit}.service"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return r.stdout.strip() == "active"

    def _check_services_running(self):
        c = self.check("All services running")
        all_ok = True
        services = [
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
        for svc in services:
            active = self._systemd_active(svc)
            child = Check(svc, passed=active)
            if not active:
                child.detail = "not running"
                all_ok = False
            c.children.append(child)
        if all_ok:
            c.ok()
        else:
            c.fail("some services are not running")

    def _check_service_apis(self):
        checks = [
            (
                "Sonarr API",
                "http://127.0.0.1:8989/api/v3/system/status",
                {"X-Api-Key": get_secret("sonarr/api_key") or ""},
            ),
            (
                "Radarr API",
                "http://127.0.0.1:7878/api/v3/system/status",
                {"X-Api-Key": get_secret("radarr/api_key") or ""},
            ),
            (
                "Lidarr API",
                "http://127.0.0.1:8686/api/v1/system/status",
                {"X-Api-Key": get_secret("lidarr/api_key") or ""},
            ),
            (
                "Prowlarr API",
                "http://127.0.0.1:9696/api/v1/system/status",
                {"X-Api-Key": get_secret("prowlarr/api_key") or ""},
            ),
            ("Jellyfin API", "http://127.0.0.1:8096/system/info/public", {}),
            (
                "Seerr API",
                "http://127.0.0.1:5055/api/v1/status",
                {"X-Api-Key": get_secret("seerr/api_key") or ""},
            ),
            (
                "Jellyfin auth",
                "http://127.0.0.1:8096/system/info",
                {"X-Emby-Token": get_secret("jellyfin/api_key") or ""},
            ),
        ]

        c = self.check("Service APIs accessible")
        all_ok = True
        for name, url, headers in checks:
            status, data, err = api_get(url, headers)
            child = Check(name)
            if status in (200, 204):
                child.ok(f"HTTP {status}")
            else:
                child.fail(f"HTTP {status}: {err or 'no response'}")
                all_ok = False
            c.children.append(child)

        if all_ok:
            c.ok()
        else:
            c.fail("some APIs are not accessible")

    def _check_cross_service_integration(self):
        c = self.check("Service-to-service integration")

        # Radarr → qBittorrent
        radarr_key = get_secret("radarr/api_key") or ""
        radarr_dc = Check("Radarr → qBittorrent download client")
        status, data, err = api_get(
            "http://127.0.0.1:7878/api/v3/downloadclient",
            {"X-Api-Key": radarr_key},
        )
        if data:
            clients = [dc for dc in data if "qbittorrent" in json.dumps(dc).lower()]
            if clients:
                radarr_dc.ok(f"found {len(clients)} qBittorrent client(s)")
            else:
                radarr_dc.fail("no qBittorrent download client configured")
        else:
            radarr_dc.fail(f"HTTP {status}: {err}")
        c.children.append(radarr_dc)

        # Sonarr → qBittorrent
        sonarr_key = get_secret("sonarr/api_key") or ""
        sonarr_dc = Check("Sonarr → qBittorrent download client")
        status, data, err = api_get(
            "http://127.0.0.1:8989/api/v3/downloadclient",
            {"X-Api-Key": sonarr_key},
        )
        if data:
            clients = [dc for dc in data if "qbittorrent" in json.dumps(dc).lower()]
            if clients:
                sonarr_dc.ok(f"found {len(clients)} qBittorrent client(s)")
            else:
                sonarr_dc.fail("no qBittorrent download client configured")
        else:
            sonarr_dc.fail(f"HTTP {status}: {err}")
        c.children.append(sonarr_dc)

        # Prowlarr → Sonarr sync
        prowlarr_key = get_secret("prowlarr/api_key") or ""
        prowlarr_sonarr = Check("Prowlarr → Sonarr app sync")
        status, data, err = api_get(
            "http://127.0.0.1:9696/api/v1/applications",
            {"X-Api-Key": prowlarr_key},
        )
        if data:
            sonarr_apps = [a for a in data if "sonarr" in json.dumps(a).lower()]
            if sonarr_apps:
                synced = all(a.get("syncLevel", "") == "fullSync" for a in sonarr_apps)
                if synced:
                    prowlarr_sonarr.ok(f"{len(sonarr_apps)} Sonarr app(s) synced")
                else:
                    prowlarr_sonarr.fail("Sonarr app exists but not full sync")
            else:
                prowlarr_sonarr.fail("no Sonarr application configured in Prowlarr")
        else:
            prowlarr_sonarr.fail(f"HTTP {status}: {err}")
        c.children.append(prowlarr_sonarr)

        # Prowlarr → Radarr sync
        prowlarr_radarr = Check("Prowlarr → Radarr app sync")
        status, data, err = api_get(
            "http://127.0.0.1:9696/api/v1/applications",
            {"X-Api-Key": prowlarr_key},
        )
        if data:
            radarr_apps = [a for a in data if "radarr" in json.dumps(a).lower()]
            if radarr_apps:
                synced = all(a.get("syncLevel", "") == "fullSync" for a in radarr_apps)
                if synced:
                    prowlarr_radarr.ok(f"{len(radarr_apps)} Radarr app(s) synced")
                else:
                    prowlarr_radarr.fail("Radarr app exists but not full sync")
            else:
                prowlarr_radarr.fail("no Radarr application configured in Prowlarr")
        else:
            prowlarr_radarr.fail(f"HTTP {status}: {err}")
        c.children.append(prowlarr_radarr)

        # Bazarr → Sonarr
        bazarr_key = get_secret("bazarr/api_key") or ""
        bazarr_sonarr = Check("Bazarr → Sonarr connection")
        status, data, err = api_get(
            "http://127.0.0.1:6767/api/system/settings",
            {"X-Api-Key": bazarr_key},
        )
        if data:
            sonarr_enabled = data.get("general", {}).get("use_sonarr", False)
            if sonarr_enabled:
                bazarr_sonarr.ok("Sonarr integration enabled")
            else:
                bazarr_sonarr.fail("Sonarr integration not enabled in Bazarr")
        else:
            bazarr_sonarr.fail(f"HTTP {status}: {err}")
        c.children.append(bazarr_sonarr)

        # Bazarr → Radarr
        bazarr_radarr = Check("Bazarr → Radarr connection")
        if data:
            radarr_enabled = data.get("general", {}).get("use_radarr", False)
            if radarr_enabled:
                bazarr_radarr.ok("Radarr integration enabled")
            else:
                bazarr_radarr.fail("Radarr integration not enabled in Bazarr")
        else:
            bazarr_radarr.fail("could not read Bazarr settings")
        c.children.append(bazarr_radarr)

        # Seerr → Jellyfin
        seerr_key = get_secret("seerr/api_key") or ""
        seerr_jf = Check("Seerr → Jellyfin connection")
        status, data, err = api_get(
            "http://127.0.0.1:5055/api/v1/settings/jellyfin",
            {"X-Api-Key": seerr_key},
        )
        if data:
            if data.get("hostname"):
                seerr_jf.ok(f"Jellyfin at {data['hostname']}:{data.get('port', 8096)}")
            else:
                seerr_jf.fail("Jellyfin not configured in Seerr")
        else:
            seerr_jf.fail(f"HTTP {status}: {err}")
        c.children.append(seerr_jf)

        # Seerr → Radarr
        seerr_radarr = Check("Seerr → Radarr connection")
        status, data, err = api_get(
            "http://127.0.0.1:5055/api/v1/settings/radarr",
            {"X-Api-Key": seerr_key},
        )
        if data:
            enabled = any(
                svc.get("isDefault")
                for svc in (data if isinstance(data, list) else [data])
            )
            if enabled:
                seerr_radarr.ok("Radarr configured as default")
            else:
                seerr_radarr.fail("no default Radarr configured in Seerr")
        else:
            seerr_radarr.fail(f"HTTP {status}: {err}")
        c.children.append(seerr_radarr)

        # Seerr → Sonarr
        seerr_sonarr = Check("Seerr → Sonarr connection")
        status, data, err = api_get(
            "http://127.0.0.1:5055/api/v1/settings/sonarr",
            {"X-Api-Key": seerr_key},
        )
        if data:
            enabled = any(
                svc.get("isDefault")
                for svc in (data if isinstance(data, list) else [data])
            )
            if enabled:
                seerr_sonarr.ok("Sonarr configured as default")
            else:
                seerr_sonarr.fail("no default Sonarr configured in Seerr")
        else:
            seerr_sonarr.fail(f"HTTP {status}: {err}")
        c.children.append(seerr_sonarr)

        passed = all(child.passed for child in c.children)
        if passed:
            c.ok()
        else:
            c.fail("some integrations are missing")

    def _check_prowlarr_indexers(self):
        c = self.check("Prowlarr indexers configured")
        prowlarr_key = get_secret("prowlarr/api_key") or ""
        status, data, err = api_get(
            "http://127.0.0.1:9696/api/v1/indexer",
            {"X-Api-Key": prowlarr_key},
        )
        if data:
            enabled = [i for i in data if i.get("enable")]
            if enabled:
                c.ok(f"{len(enabled)} indexer(s) enabled")
            else:
                c.fail("no indexers enabled")
        else:
            c.fail(f"HTTP {status}: {err}")

    def _check_radarr_sonarr_config(self):
        c = self.check("Radarr & Sonarr configuration")
        radarr_key = get_secret("radarr/api_key") or ""
        sonarr_key = get_secret("sonarr/api_key") or ""

        # Radarr root folder
        root = Check("Radarr root folder configured")
        status, data, err = api_get(
            "http://127.0.0.1:7878/api/v3/rootfolder",
            {"X-Api-Key": radarr_key},
        )
        if data and len(data) > 0:
            root.ok(f"path: {data[0].get('path', 'unknown')}")
        else:
            root.fail("no root folder configured" if data else f"HTTP {status}: {err}")
        c.children.append(root)

        # Radarr rename enabled
        rename = Check("Radarr rename movies enabled")
        status, data, err = api_get(
            "http://127.0.0.1:7878/api/v3/config/naming",
            {"X-Api-Key": radarr_key},
        )
        if data:
            if data.get("renameEpisodes", False):
                rename.ok()
            else:
                rename.fail("rename not enabled")
        else:
            rename.fail(f"HTTP {status}: {err}")
        c.children.append(rename)

        # Radarr → Jellyfin connect
        jf_radarr = Check("Radarr → Jellyfin notification")
        status, data, err = api_get(
            "http://127.0.0.1:7878/api/v3/notification",
            {"X-Api-Key": radarr_key},
        )
        if data:
            jf = [n for n in data if "jellyfin" in json.dumps(n).lower()]
            if jf:
                jf_radarr.ok(f"{len(jf)} Jellyfin notification(s) configured")
            else:
                jf_radarr.fail("no Jellyfin notification configured")
        else:
            jf_radarr.fail(f"HTTP {status}: {err}")
        c.children.append(jf_radarr)

        # Sonarr root folder
        s_root = Check("Sonarr root folder configured")
        status, data, err = api_get(
            "http://127.0.0.1:8989/api/v3/rootfolder",
            {"X-Api-Key": sonarr_key},
        )
        if data and len(data) > 0:
            s_root.ok(f"path: {data[0].get('path', 'unknown')}")
        else:
            s_root.fail(
                "no root folder configured" if data else f"HTTP {status}: {err}"
            )
        c.children.append(s_root)

        # Sonarr rename enabled
        s_rename = Check("Sonarr rename episodes enabled")
        status, data, err = api_get(
            "http://127.0.0.1:8989/api/v3/config/naming",
            {"X-Api-Key": sonarr_key},
        )
        if data:
            if data.get("renameEpisodes", False):
                s_rename.ok()
            else:
                s_rename.fail("rename not enabled")
        else:
            s_rename.fail(f"HTTP {status}: {err}")
        c.children.append(s_rename)

        # Sonarr → Jellyfin connect
        jf_sonarr = Check("Sonarr → Jellyfin notification")
        status, data, err = api_get(
            "http://127.0.0.1:8989/api/v3/notification",
            {"X-Api-Key": sonarr_key},
        )
        if data:
            jf = [n for n in data if "jellyfin" in json.dumps(n).lower()]
            if jf:
                jf_sonarr.ok(f"{len(jf)} Jellyfin notification(s) configured")
            else:
                jf_sonarr.fail("no Jellyfin notification configured")
        else:
            jf_sonarr.fail(f"HTTP {status}: {err}")
        c.children.append(jf_sonarr)

        passed = all(child.passed for child in c.children)
        if passed:
            c.ok()
        else:
            c.fail("some Radarr/Sonarr config items are missing")

    def _check_bazarr_config(self):
        c = self.check("Bazarr configuration")
        bazarr_key = get_secret("bazarr/api_key") or ""
        status, data, err = api_get(
            "http://127.0.0.1:6767/api/system/settings",
            {"X-Api-Key": bazarr_key},
        )
        if not data:
            c.fail(f"cannot reach Bazarr API: HTTP {status} {err}")
            return

        # Languages
        langs = Check("Bazarr languages configured")
        s2, d2, e2 = api_get(
            "http://127.0.0.1:6767/api/system/languages",
            {"X-Api-Key": bazarr_key},
        )
        if d2:
            enabled = [l for l in d2 if l.get("enabled")]
            if enabled:
                codes = ", ".join(l.get("code2", "?") for l in enabled)
                langs.ok(f"enabled: {codes}")
            else:
                langs.fail("no languages enabled")
        else:
            langs.fail(f"HTTP {s2}: {e2}")
        c.children.append(langs)

        # Language profiles
        profiles = Check("Bazarr language profiles created")
        s2, d2, e2 = api_get(
            "http://127.0.0.1:6767/api/system/languages/profiles",
            {"X-Api-Key": bazarr_key},
        )
        if d2 and len(d2) > 0:
            names = ", ".join(p.get("name", "?") for p in d2)
            profiles.ok(f"profiles: {names}")
        else:
            profiles.fail("no language profiles" if d2 else f"HTTP {s2}: {e2}")
        c.children.append(profiles)

        # Subtitle providers
        providers = Check("Bazarr subtitle providers configured")
        if data:
            enabled_providers = data.get("general", {}).get("enabled_providers", [])
            if enabled_providers and len(enabled_providers) > 0:
                providers.ok(f"{len(enabled_providers)} provider(s) enabled")
            else:
                providers.fail("no subtitle providers enabled")
        else:
            providers.fail("cannot read settings")
        c.children.append(providers)

        passed = all(child.passed for child in c.children)
        if passed:
            c.ok()
        else:
            c.fail("some Bazarr config items are missing")

    def _print_report(self):
        passed = sum(1 for c in self._flatten(self.results) if c.passed)
        total = sum(1 for _ in self._flatten(self.results))

        print()
        print("=" * 60)
        print("  Nixflix Health Check")
        print("=" * 60)
        print()
        for c in self.results:
            self._print_check(c, 0)
        print()
        print("=" * 60)
        if passed == total:
            print(f"  ✓ {passed}/{total} checks passed — all good!")
        else:
            print(f"  ✗ {passed}/{total} checks passed — {total - passed} failure(s)")
        print("=" * 60)

    def _print_check(self, c: Check, level: int):
        indent = "  " * level
        icon = "✓" if c.passed else "✗"
        if c.children:
            print(f"{indent}{icon} {c.name}")
            if c.detail:
                print(f"{indent}    → {c.detail}")
            for child in c.children:
                self._print_check(child, level + 1)
        else:
            detail = f" — {c.detail}" if c.detail else ""
            print(f"{indent}  {icon} {c.name}{detail}")

    @staticmethod
    def _flatten(checks: list[Check]):
        for c in checks:
            yield c
            yield from NixflixChecker._flatten(c.children)


def run_check():
    checker = NixflixChecker()
    checker.run_all()
    total = sum(1 for _ in checker._flatten(checker.results))
    passed = sum(1 for c in checker._flatten(checker.results) if c.passed)
    return 0 if passed == total else 1
