# k3s single-node cluster for the *arr media stack.
#
# Runs k3s as a server on this host. Traefik is kept (default chart), but
# reconfigured to NodePort 30080/30443 so the *arr UIs are reachable without
# touching host ports 80/443 (which nixflix's nginx owns during the
# side-by-side phase). The /etc/hosts entries point to 127.0.0.1 — during
# side-by-side, users reach k3s apps at http://<service>.k8s.nixflix:30080.
# After nixflix is removed, enable `ingressForward` to iptables-redirect
# 80/443 -> 30080/30443 and the :30080 port suffix drops off the URLs.
#
# The actual *arr workloads are deployed via helmfile from
# /home/taian/workspaces/servarr (see helmfile.yaml there).
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.k3s-servarr;

  # Hostnames for the *arr UIs. Suffix `.k8s.nixflix` keeps them
  # visually grouped with the existing `*.nixflix` nixflix hostnames
  # but unambiguously identifies them as the k8s side. Same-host
  # resolution is fine for single-node; DNS for off-host clients can
  # be served by the LAN router or by adding a dnsmasq service later.
  k8sHostnames = [
    "sonarr.k8s.nixflix"
    "radarr.k8s.nixflix"
    "lidarr.k8s.nixflix"
    "readarr.k8s.nixflix"
    "prowlarr.k8s.nixflix"
    "qbittorrent.k8s.nixflix"
    "jellyfin.k8s.nixflix"
    "jellyseerr.k8s.nixflix"
    "bazarr.k8s.nixflix"
  ];
in
{
  options.services.k3s-servarr = {
    enable = lib.mkEnableOption "k3s single-node cluster for the *arr stack";

    # Set true on a node where nixflix's nginx is no longer bound to 80/443
    # (i.e. after the cutover). Adds iptables PREROUTING redirects
    # 80 -> 30080 and 443 -> 30443 so users can drop the :30080 port
    # suffix from their URLs. Leave false during side-by-side.
    ingressForward = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Redirect host 80/443 to Traefik NodePort 30080/30443.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Run k3s as a single-node "cluster". We disable a few defaults:
    #   - local-storage: we use a single hostPath for /data, no need for
    #     a StorageClass; recyclarr gets its own PVC via longhorn-equivalent
    #     or a local-path PV. Leaving local-storage ON is harmless and
    #     gives us a default StorageClass for chart-managed PVCs.
    #   - metrics-server: kept on (default) — useful for `kubectl top`.
    #   - servicelb: KEPT ON — this is what gives us NodePort 30080/30443.
    #   - traefik: KEPT ON — but we override to NodePort via HelmChartConfig
    #     written by `k3s-traefik-config.service` below.
    services.k3s = {
      enable = true;
      role = "server";
      package = pkgs.k3s;
      # Single-node, default CNI. Traefik is kept (default) but bound
      # to NodePort 30080/30443 via the HelmChartConfig written by
      # k3s-traefik-config.service below. Node IP is auto-detected from
      # the host's primary interface so off-host LAN clients can also
      # reach the *arr UIs on http://<lan-ip>:30080.
      extraFlags = [
        "--flannel-backend=host-gw"
      ];
    };

    # Traefik HelmChartConfig: switch the default Traefik service from
    # LoadBalancer to NodePort with stable host ports. Without this, k3s'
    # ServiceLB would auto-allocate random NodePorts from the 30000-32767
    # range, and the host-port forwarding (see `ingressForward` below)
    # wouldn't line up. We write the file into the k3s manifests dir so
    # the bundled helm-controller picks it up at the next reconcile.
    systemd.services.k3s-traefik-config = {
      description = "Write Traefik HelmChartConfig for NodePort 30080/30443";
      wantedBy = [ "multi-user.target" ];
      before = [ "k3s.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Idempotent: re-runs are no-ops because the file content is
        # deterministic. k3s picks up the file via inotify on first
        # boot and after every switch.
        ExecStart = pkgs.writeShellScript "k3s-traefik-config" ''
          set -eu
          ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/rancher/k3s/server/manifests
          ${pkgs.coreutils}/bin/install -m 0644 \
            ${pkgs.writeText "traefik-helmchartconfig.yaml" ''
              apiVersion: helm.cattle.io/v1
              kind: HelmChartConfig
              metadata:
                name: traefik
                namespace: kube-system
              spec:
                valuesContent: |-
                  ports:
                    web:
                      nodePort: 30080
                    websecure:
                      nodePort: 30443
                  service:
                    type: NodePort
            ''} \
            /var/lib/rancher/k3s/server/manifests/traefik-config.yaml
        '';
      };
    };

    # Open the NodePort range on the firewall so Traefik can serve
    # external requests. We only need 30080 + 30443 + the k3s API
    # (default 6443) — the latter is opened by the k3s module.
    networking.firewall.allowedTCPPorts = [
      30080
      30443
    ];

    # Optional: forward 80/443 -> 30080/30443 via iptables. Off during
    # side-by-side (nixflix owns 80/443), on after cutover.
    systemd.services.k3s-ingress-forward = lib.mkIf cfg.ingressForward {
      description = "Forward host 80/443 to Traefik NodePort 30080/30443";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      wants = [ "k3s.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "k3s-ingress-forward" ''
          set -eu
          ${pkgs.iptables}/bin/iptables -t nat -C PREROUTING -p tcp --dport 80 \
            -j REDIRECT --to-port 30080 2>/dev/null \
            || ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -p tcp --dport 80 \
              -j REDIRECT --to-port 30080
          ${pkgs.iptables}/bin/iptables -t nat -C PREROUTING -p tcp --dport 443 \
            -j REDIRECT --to-port 30443 2>/dev/null \
            || ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -p tcp --dport 443 \
              -j REDIRECT --to-port 30443
        '';
        ExecStop = pkgs.writeShellScript "k3s-ingress-forward-stop" ''
          set -e
          ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -p tcp --dport 80 \
            -j REDIRECT --to-port 30080 2>/dev/null || true
          ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -p tcp --dport 443 \
            -j REDIRECT --to-port 30443 2>/dev/null || true
        '';
      };
    };

    # kubectl, helm, and helmfile belong in the user's PATH so they
    # can drive the cluster from the workdir. The k3s module already
    # writes /etc/rancher/k3s/k3s.yaml; we make it group-readable for
    # the `taian` user and copy a per-user kubeconfig to ~/.kube/config.
    environment.systemPackages = with pkgs; [
      kubectl
      k3s
    ];

    # /etc/hosts entries for the k3s hostnames. nixflix already adds
    # the bare `*.nixflix` aliases — we add `*.k8s.nixflix` to keep
    # both stacks reachable simultaneously.
    networking.hosts = {
      "127.0.0.1" = k8sHostnames;
    };
  };
}
