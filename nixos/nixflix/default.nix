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
        Preferences.Downloads = {
          SavePath = "/data/downloads/complete";
          TempPath = "/data/downloads/incomplete";
          TempPathEnabled = true;
        };
        Preferences.WebUI = {
          Username = "admin";
          Password_PBKDF2 = "@ByteArray(YWRtaW4==:Lki2TfJQMX2GUP8t6S4sNyLao1XTg/XdkbcsX1ht5UVHybIkvTm6L+TB9tZ2xt8xRy9iW8quaraTOweXb495rg==)";
        };
      };
    };

    jellyfin = {
      enable = true;
      apiKey._secret = config.sops.secrets."jellyfin/api_key".path;
      network = {
        knownProxies = [
          "127.0.0.1"
          "192.168.68.1"
        ];
        localNetworkAddresses = [
          "127.0.0.1"
          "192.168.68.101"
        ];
        enablePublishedServerUriByRequest = true;
      };
      openFirewall = true;
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

    # Oneshot service to configure languages, quality settings, scan schedule, and providers
    # after Bazarr starts. Provider API keys (e.g. OpenSubtitles.com) still need to be
    # added via the Bazarr UI; this service enables the free providers and applies the
    # rest of the tutorial's settings declaratively.
    bazarr-setup = {
      description = "Configure Bazarr languages, quality settings, scan schedule, and providers";
      after = [
        "bazarr.service"
        "network-online.target"
      ];
      requires = [ "bazarr.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "bazarr";
        Group = config.services.bazarr.group;
        Restart = "on-failure";
        RestartSec = "10s";
      };

      script =
        let
          apiKeyFile = config.sops.secrets."bazarr/api_key".path;
          port = toString config.services.bazarr.listenPort;
          curl = "${pkgs.curl.bin}/bin/curl";
        in
        ''
          set -eu

          API_KEY=$(cat ${apiKeyFile})
          BASE_URL="http://127.0.0.1:${port}"

          echo "Waiting for Bazarr API..."
          for i in $(seq 1 60); do
            if ${curl} -sf "$BASE_URL/api/system/settings" -H "X-Api-Key: $API_KEY" > /dev/null 2>&1; then
              echo "Bazarr API ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "Timed out waiting for Bazarr"
              exit 1
            fi
            sleep 2
          done

          echo "Enabling Portuguese..."
          ${curl} -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "languages-enabled=pt" > /dev/null || true

          echo "Enabling English..."
          ${curl} -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "languages-enabled=en" > /dev/null || true

          echo "Creating language profile..."
          ${curl} -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d 'languages-profiles=[{"profileId":1,"name":"Portuguese + English","cutoff":"pt","items":[{"language":"pt","audio_exclude":false,"forced":false,"hi":false},{"language":"en","audio_exclude":false,"forced":false,"hi":false}],"mustContain":"","mustNotContain":"","originalFormat":null,"tag":""}]' > /dev/null || true

          # --- Subtitle providers per Jellyfin Full Automation Guide ---
          # Addic7ed (best for TV) and Podnapisi (good European coverage) work without
          # credentials; OpenSubtitles.com is also enabled so the user just needs to
          # drop their free API key in the Bazarr UI.
          echo "Enabling subtitle providers (Addic7ed, Podnapisi, OpenSubtitles)..."
          ${curl} -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "general-enabled_providers=addic7ed,podnapisi,opensubtitles" > /dev/null || true

          # --- Quality settings per Jellyfin Full Automation Guide ---
          echo "Setting subtitle score threshold to 90..."
          ${curl} -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "general-minimum_score=90" \
            -d "general-minimum_score_movie=90" > /dev/null || true

          echo "Enabling subtitle post-processing / sync..."
          ${curl} -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "general-use_postprocessing=true" \
            -d "general-use_postprocessing_threshold=true" \
            -d "general-postprocessing_threshold=90" > /dev/null || true

          echo "Scheduling full scan at 3 AM daily..."
          ${curl} -sf -X POST "$BASE_URL/api/system/settings" \
            -H "X-Api-Key: $API_KEY" \
            -d "sonarr-full_update=Daily" \
            -d "sonarr-full_update_hour=3" \
            -d "radarr-full_update=Daily" \
            -d "radarr-full_update_hour=3" > /dev/null || true

          echo "Bazarr setup complete"
        '';
    };

    # Radarr → Jellyfin Connect notification: tells Jellyfin to refresh its library
    # whenever Radarr imports a movie. Mirrors Step 3 of the Jellyfin Full Automation
    # Guide (2026). Idempotent: matches by name, creates if missing, updates otherwise.
    radarr-jellyfin-connect = mkIf config.nixflix.radarr.enable {
      description = "Configure Radarr Jellyfin Connect notification";
      after = [
        "radarr.service"
        "radarr-config.service"
        "network-online.target"
      ];
      requires = [ "radarr.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";
        LoadCredential =
          let
            radarrKeyFile = config.nixflix.radarr.config.apiKey._secret or null;
            jellyfinKeyFile = config.sops.secrets."jellyfin/api_key".path;
          in
          [
            "radarr_api_key:${
              if config.nixflix.radarr.config.apiKey._secret or null != null then
                config.nixflix.radarr.config.apiKey._secret
              else
                pkgs.writeText "radarr-api-key" config.nixflix.radarr.config.apiKey
            }"
            "jellyfin_api_key:${jellyfinKeyFile}"
          ];
      };

      script =
        let
          radarrPort = toString config.nixflix.radarr.config.hostConfig.port;
          jellyfinPort = toString config.nixflix.jellyfin.network.internalHttpPort;
          curl = "${pkgs.curl.bin}/bin/curl";
          jq = "${pkgs.jq}/bin/jq";
        in
        ''
          set -eu

          RADARR_API_KEY=$(cat /run/credentials/radarr-jellyfin-connect.service/radarr_api_key)
          JELLYFIN_API_KEY=$(cat /run/credentials/radarr-jellyfin-connect.service/jellyfin_api_key)
          BASE_URL="http://127.0.0.1:${radarrPort}/api/v3"
          JELLYFIN_URL="http://127.0.0.1:${jellyfinPort}"

          echo "Waiting for Radarr API..."
          for i in $(seq 1 60); do
            if ${curl} -sf "$BASE_URL/system/status" -H "X-Api-Key: $RADARR_API_KEY" > /dev/null 2>&1; then
              echo "Radarr API ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "Timed out waiting for Radarr"
              exit 1
            fi
            sleep 2
          done

          echo "Fetching notification schemas..."
          SCHEMAS=$(${curl} -s "$BASE_URL/notification/schema" -H "X-Api-Key: $RADARR_API_KEY")
          SCHEMA=$(echo "$SCHEMAS" | ${jq} -r '.[] | select(.implementationName == "Jellyfin") | @json' | head -n1)

          if [ -z "$SCHEMA" ] || [ "$SCHEMA" = "null" ]; then
            echo "Jellyfin notification schema not found in Radarr"
            exit 1
          fi

          echo "Fetching existing notifications..."
          EXISTING=$(${curl} -s "$BASE_URL/notification" -H "X-Api-Key: $RADARR_API_KEY")

          EXISTING_ID=$(echo "$EXISTING" | ${jq} -r --arg impl Jellyfin \
            '.[] | select(.implementation == $impl) | .id' | head -n1)

          # Build the notification payload from the schema
          NOTIFICATION=$(echo "$SCHEMA" | ${jq} \
            --arg host "$JELLYFIN_URL" \
            --arg apiKey "$JELLYFIN_API_KEY" \
            '
              .name = "Jellyfin"
              | .onGrab = false
              | .onDownload = true
              | .onUpgrade = true
              | .onRename = true
              | .onMovieAdded = true
              | .onMovieFileDeleted = true
              | .onHealthIssue = false
              | .onHealthRestored = false
              | .onApplicationUpdate = true
              | .onManualInteractionRequired = false
              | .includeHealthWarnings = false
              | .fields |= map(
                  if .name == "host" then .value = $host
                  elif .name == "apiKey" then .value = $apiKey
                  elif .name == "useSsl" then .value = false
                  elif .name == "urlBase" then .value = ""
                  elif .name == "displaySeconds" then .value = 0
                  elif .name == "enabled" then .value = true
                  else . end
                )
            ')

          if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
            echo "Updating existing Radarr → Jellyfin notification (ID: $EXISTING_ID)..."
            HTTP_CODE=$(${curl} -s -o /tmp/put_response -w "%{http_code}" \
              -X PUT "$BASE_URL/notification/$EXISTING_ID" \
              -H "X-Api-Key: $RADARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NOTIFICATION")
            if [ "$HTTP_CODE" -ge 400 ]; then
              echo "PUT failed (HTTP $HTTP_CODE):"
              cat /tmp/put_response
              exit 1
            fi
          else
            echo "Creating Radarr → Jellyfin notification..."
            HTTP_CODE=$(${curl} -s -o /tmp/post_response -w "%{http_code}" \
              -X POST "$BASE_URL/notification" \
              -H "X-Api-Key: $RADARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NOTIFICATION")
            if [ "$HTTP_CODE" -ge 400 ]; then
              echo "POST failed (HTTP $HTTP_CODE):"
              cat /tmp/post_response
              exit 1
            fi
          fi

          echo "Radarr → Jellyfin Connect notification configured"
        '';
    };

    # Sonarr → Jellyfin Connect notification: same idea as Radarr's but for series/episodes.
    # Mirrors Step 4 of the Jellyfin Full Automation Guide (2026).
    sonarr-jellyfin-connect = mkIf config.nixflix.sonarr.enable {
      description = "Configure Sonarr Jellyfin Connect notification";
      after = [
        "sonarr.service"
        "sonarr-config.service"
        "network-online.target"
      ];
      requires = [ "sonarr.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";
        LoadCredential =
          let
            sonarrKeyFile = config.nixflix.sonarr.config.apiKey._secret or null;
            jellyfinKeyFile = config.sops.secrets."jellyfin/api_key".path;
          in
          [
            "sonarr_api_key:${
              if config.nixflix.sonarr.config.apiKey._secret or null != null then
                config.nixflix.sonarr.config.apiKey._secret
              else
                pkgs.writeText "sonarr-api-key" config.nixflix.sonarr.config.apiKey
            }"
            "jellyfin_api_key:${jellyfinKeyFile}"
          ];
      };

      script =
        let
          sonarrPort = toString config.nixflix.sonarr.config.hostConfig.port;
          jellyfinPort = toString config.nixflix.jellyfin.network.internalHttpPort;
          curl = "${pkgs.curl.bin}/bin/curl";
          jq = "${pkgs.jq}/bin/jq";
        in
        ''
          set -eu

          SONARR_API_KEY=$(cat /run/credentials/sonarr-jellyfin-connect.service/sonarr_api_key)
          JELLYFIN_API_KEY=$(cat /run/credentials/sonarr-jellyfin-connect.service/jellyfin_api_key)
          BASE_URL="http://127.0.0.1:${sonarrPort}/api/v3"
          JELLYFIN_URL="http://127.0.0.1:${jellyfinPort}"

          echo "Waiting for Sonarr API..."
          for i in $(seq 1 60); do
            if ${curl} -sf "$BASE_URL/system/status" -H "X-Api-Key: $SONARR_API_KEY" > /dev/null 2>&1; then
              echo "Sonarr API ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "Timed out waiting for Sonarr"
              exit 1
            fi
            sleep 2
          done

          echo "Fetching notification schemas..."
          SCHEMAS=$(${curl} -s "$BASE_URL/notification/schema" -H "X-Api-Key: $SONARR_API_KEY")
          SCHEMA=$(echo "$SCHEMAS" | ${jq} -r '.[] | select(.implementationName == "Jellyfin") | @json' | head -n1)

          if [ -z "$SCHEMA" ] || [ "$SCHEMA" = "null" ]; then
            echo "Jellyfin notification schema not found in Sonarr"
            exit 1
          fi

          echo "Fetching existing notifications..."
          EXISTING=$(${curl} -s "$BASE_URL/notification" -H "X-Api-Key: $SONARR_API_KEY")

          EXISTING_ID=$(echo "$EXISTING" | ${jq} -r --arg impl Jellyfin \
            '.[] | select(.implementation == $impl) | .id' | head -n1)

          NOTIFICATION=$(echo "$SCHEMA" | ${jq} \
            --arg host "$JELLYFIN_URL" \
            --arg apiKey "$JELLYFIN_API_KEY" \
            '
              .name = "Jellyfin"
              | .onGrab = false
              | .onDownload = true
              | .onUpgrade = true
              | .onRename = true
              | .onSeriesAdd = true
              | .onSeriesDelete = true
              | .onEpisodeFileDeleted = true
              | .onEpisodeFileAdded = true
              | .onHealthIssue = false
              | .onHealthRestored = false
              | .onApplicationUpdate = true
              | .onManualInteractionRequired = false
              | .includeHealthWarnings = false
              | .fields |= map(
                  if .name == "host" then .value = $host
                  elif .name == "apiKey" then .value = $apiKey
                  elif .name == "useSsl" then .value = false
                  elif .name == "urlBase" then .value = ""
                  elif .name == "displaySeconds" then .value = 0
                  elif .name == "enabled" then .value = true
                  else . end
                )
            ')

          if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
            echo "Updating existing Sonarr → Jellyfin notification (ID: $EXISTING_ID)..."
            HTTP_CODE=$(${curl} -s -o /tmp/put_response -w "%{http_code}" \
              -X PUT "$BASE_URL/notification/$EXISTING_ID" \
              -H "X-Api-Key: $SONARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NOTIFICATION")
            if [ "$HTTP_CODE" -ge 400 ]; then
              echo "PUT failed (HTTP $HTTP_CODE):"
              cat /tmp/put_response
              exit 1
            fi
          else
            echo "Creating Sonarr → Jellyfin notification..."
            HTTP_CODE=$(${curl} -s -o /tmp/post_response -w "%{http_code}" \
              -X POST "$BASE_URL/notification" \
              -H "X-Api-Key: $SONARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NOTIFICATION")
            if [ "$HTTP_CODE" -ge 400 ]; then
              echo "POST failed (HTTP $HTTP_CODE):"
              cat /tmp/post_response
              exit 1
            fi
          fi

          echo "Sonarr → Jellyfin Connect notification configured"
        '';
    };
  };
}
