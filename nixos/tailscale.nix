# Tailscale: WireGuard-based mesh VPN for remote access to the nixflix
# stack. All services stay bound to 127.0.0.1; `tailscale serve` exposes
# the local nginx (which reverse-proxies bazarr.nixflix, seerr.nixflix,
# jellyfin.nixflix, sonarr.nixflix, etc.) over Tailscale's userspace HTTPS
# proxy with Tailscale-issued certs. No firewall ports are opened, no
# public DNS, no ACME.
#
# Boot sequence:
#   1. services.tailscale.enable pulls in pkgs.tailscale and starts
#      tailscaled (waits for auth on first boot).
#   2. tailscale-up.service runs `tailscale up --authkey=...` using the
#      secret mounted at /run/secrets/tailscale/auth_key.
#   3. tailscale-serve.service runs `tailscale serve --bg --https=443
#      http://localhost:80` so the existing nginx vhosts are reachable
#      at https://<host>.<tailnet>.ts.net from any tailnet device.
#
# To use: install Tailscale on phone/laptop, sign in to the same
# tailnet, browse to https://<host>.<tailnet>.ts.net.
#
# Before nixup: `sops secrets.yaml` and add a `tailscale/auth_key: ...`
# line. Generate the key at https://login.tailscale.com/admin/settings/keys.
# Tag the key `tag:browser` (or any reusable auth key) so the daemon
# does not need an admin to approve it on first boot.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale/auth_key".path;
    # We do not advertise routes or run as an exit node.
    useRoutingFeatures = "none";
  };

  # The auth key in secrets.yaml is consumed by the tailscale-up.service
  # below via systemd LoadCredential. Mode 0400 + root owner means only
  # root can read the file, and systemd hands a copy to the unit's
  # credential dir (/run/credentials/...) for the service to consume.
  sops.secrets."tailscale/auth_key" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # First-boot authentication. tailscaled starts on boot but waits for
  # `tailscale up`; this unit does that with the secret-mounted auth
  # key. Idempotent: if the daemon is already authenticated, the unit
  # exits 0 and stays "active" (RemainAfterExit).
  systemd.services.tailscale-up = {
    description = "Authenticate this host to the tailnet using the sops-mounted auth key";
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    requires = [ "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10s";
      LoadCredential = [
        "tailscale_auth_key:${config.sops.secrets."tailscale/auth_key".path}"
      ];
    };

    script = ''
      set -eu
      AUTH_KEY=$(cat /run/credentials/tailscale-up.service/tailscale_auth_key)
      TAILSCALE=${pkgs.tailscale}/bin/tailscale

      # Skip if already authenticated (e.g. after a reboot).
      if $TAILSCALE status --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
        echo "Tailscale already authenticated, skipping tailscale up"
        exit 0
      fi

      echo "Authenticating this host to Tailscale..."
      $TAILSCALE up --authkey="$AUTH_KEY" --accept-routes
    '';
  };

  # Expose the local nginx (which reverse-proxies bazarr.nixflix,
  # seerr.nixflix, jellyfin.nixflix, sonarr.nixflix, radarr.nixflix,
  # lidarr.nixflix, prowlarr.nixflix, qbittorrent.nixflix) over
  # Tailscale HTTPS. Idempotent: `tailscale serve` replaces any
  # existing serve config.
  systemd.services.tailscale-serve = {
    description = "Expose local nginx vhosts over Tailscale HTTPS";
    after = [
      "tailscale-up.service"
      "nginx.service"
    ];
    requires = [ "tailscale-up.service" ];
    wants = [ "nginx.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10s";
    };

    script = ''
      set -eu
      TAILSCALE=${pkgs.tailscale}/bin/tailscale
      echo "Exposing local nginx on Tailscale HTTPS (port 443)..."
      $TAILSCALE serve --bg --https=443 http://localhost:80
    '';
  };
}
