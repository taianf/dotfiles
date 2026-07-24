# Nixflix — media server stack (Sonarr, Radarr, Jellyfin, etc.)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  sops.secrets = {
    "sonarr/api_key" = { };
    "sonarr/password" = { };
    "radarr/api_key" = { };
    "radarr/password" = { };
    "lidarr/api_key" = { };
    "lidarr/password" = { };
    "prowlarr/api_key" = { };
    "prowlarr/password" = { };
    "qbittorrent/password" = { };
    "jellyfin/api_key" = { };
    "jellyfin/admin_password" = { };
    "seerr/api_key" = { };
    "bazarr/api_key" = {
      group = config.nixflix.globals.libraryOwner.group;
      mode = "0440";
    };
  };

  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/.state";
    mediaUsers = [ "taian" ];

    nginx = {
      enable = true;
      addHostsEntries = true;
    };

    postgres.enable = true;

    sonarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."sonarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."sonarr/password".path;
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."radarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."radarr/password".path;
      };
    };

    lidarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."lidarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."lidarr/password".path;
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."prowlarr/api_key".path;
        hostConfig.password._secret = config.sops.secrets."prowlarr/password".path;
        indexers = [
          { name = "The Pirate Bay"; }
          { name = "1337x"; }
          { name = "TorrentGalaxy"; }
          { name = "YTS"; }
          { name = "LimeTorrents"; }
        ];
      };
    };

    torrentClients.qbittorrent = {
      enable = true;
      webuiPort = 8080;
      password._secret = config.sops.secrets."qbittorrent/password".path;
      serverConfig = {
        LegalNotice.Accepted = true;
        Preferences.WebUI = {
          Username = "admin";
          Password_PBKDF2 = "@ByteArray(YWRtaW4==:Lki2TfJQMX2GUP8t6S4sNyLao1XTg/XdkbcsX1ht5UVHybIkvTm6L+TB9tZ2xt8xRy9iW8quaraTOweXb495rg==)";
        };
      };
    };

    jellyfin = {
      enable = true;
      apiKey._secret = config.sops.secrets."jellyfin/api_key".path;
      network.knownProxies = [
        "127.0.0.1"
        "192.168.68.1"
      ];
      network.enablePublishedServerUriByRequest = true;
      users = {
        admin = {
          mutable = false;
          policy.isAdministrator = true;
          password._secret = config.sops.secrets."jellyfin/admin_password".path;
        };
      };
    };

    seerr = {
      enable = true;
      apiKey._secret = config.sops.secrets."seerr/api_key".path;
    };

    # TRaSH quality profiles via Recyclarr — syncs community-tested profiles
    # See: https://trash-guides.info
    recyclarr = {
      enable = true;
      # Selects profiles that prioritize acquisition over quality
      radarrQuality = "1080p";
      sonarrQuality = "1080p";
      # Automatically remove unmanaged quality profiles
      cleanupUnmanagedProfiles.enable = false;
    };
  };

  services.bazarr = {
    enable = true;
    dataDir = "${config.nixflix.stateDir}/bazarr";
    listenPort = 6767;
    group = config.nixflix.globals.libraryOwner.group;
    openFirewall = false;
  };

  services.nginx.virtualHosts."bazarr.nixflix" = mkIf config.nixflix.nginx.enable {
    forceSSL = config.nixflix.nginx.forceSSL;
    useACMEHost = if config.nixflix.nginx.enableACME then config.nixflix.nginx.domain else null;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
      recommendedProxySettings = true;
      proxyWebsockets = true;
      extraConfig = ''
        proxy_redirect off;
      '';
    };
  };

  networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
    "127.0.0.1" = [ "bazarr.nixflix" ];
  };

  systemd.services = {
    # Disable non-essential setup services that fail on nixup
    prowlarr-indexers.enable = mkForce false;
    seerr-setup.enable = mkForce false;
    # Seerr overrides
    seerr = {
      serviceConfig.RestrictNamespaces = mkForce false;
      serviceConfig.ExecStartPre =
        let
          dataDir = config.nixflix.seerr.dataDir or "/data/.state/seerr";
        in
        lib.mkBefore "${pkgs.coreutils}/bin/mkdir -p ${dataDir}";
    };

    # Pre-write config.yaml with sops-managed API key on first start
    bazarr = {
      preStart =
        let
          apiKeyFile = config.sops.secrets."bazarr/api_key".path;
        in
        ''
                  CONFIG_DIR=${config.services.bazarr.dataDir}/config
                  CONFIG_FILE=$CONFIG_DIR/config.yaml
                  if [ ! -f "$CONFIG_FILE" ]; then
                    mkdir -p "$CONFIG_DIR"
                    API_KEY=$(cat ${apiKeyFile})
                    cat > "$CONFIG_FILE" << EOF
          auth:
            apikey: $API_KEY
          general:
            use_sonarr: true
            use_radarr: true
          EOF
                    chown bazarr:${config.services.bazarr.group} "$CONFIG_FILE"
                    chmod 600 "$CONFIG_FILE"
                  fi
        '';
    };

    # Oneshot service to configure languages after Bazarr starts
    bazarr-setup = {
      description = "Configure Bazarr languages and profiles";
      after = [
        "bazarr.service"
        "network-online.target"
      ];
      requires = [ "bazarr.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "bazarr";
        Group = config.services.bazarr.group;
      };

      script =
        let
          apiKeyFile = config.sops.secrets."bazarr/api_key".path;
          port = toString config.services.bazarr.listenPort;
        in
        ''
          set -eu

          API_KEY=$(cat ${apiKeyFile})
          BASE_URL="http://127.0.0.1:${port}"

          echo "Waiting for Bazarr API..."
          for i in $(seq 1 30); do
            if curl -sf "$BASE_URL/api/system/settings" -H "X-Api-Key: $API_KEY" > /dev/null 2>&1; then
              echo "Bazarr API ready"
              break
            fi
            if [ "$i" -eq 30 ]; then
              echo "Timed out waiting for Bazarr"
              exit 1
            fi
            sleep 2
          done

          echo "Enabling Portuguese..."
          curl -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "languages-enabled=pt" > /dev/null

          echo "Enabling English..."
          curl -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "languages-enabled=en" > /dev/null

          echo "Creating language profile..."
          curl -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d 'languages-profiles=[{"profileId":1,"name":"Portuguese + English","cutoff":"pt","items":[{"language":"pt","audio_exclude":false,"forced":false,"hi":false},{"language":"en","audio_exclude":false,"forced":false,"hi":false}],"mustContain":"","mustNotContain":"","originalFormat":null,"tag":""}]' > /dev/null

          echo "Bazarr setup complete"
        '';
    };
  };
}
