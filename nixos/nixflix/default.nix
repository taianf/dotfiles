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
    "sonarr/api_key" = {
      # The Bazarr pre-start script (running as User=bazarr, Group=bazarr)
      # needs to read the Sonarr and Radarr API keys to write bazarr's
      # config.yaml. The 'media' group is shared by bazarr, sonarr, and
      # radarr, so group=media + mode=0440 lets bazarr read them without
      # making them world-readable. sops-nix defaults (root:root, 0400)
      # would block bazarr's pre-start with "Permission denied".
      group = "media";
      mode = "0440";
    };
    "sonarr/password" = { };
    "radarr/api_key" = {
      # See comment on sonarr/api_key above.
      group = "media";
      mode = "0440";
    };
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
      # The Bazarr service runs as User=bazarr, Group=bazarr — so the secret
      # must be readable by that group, not the media/library group.
      group = config.services.bazarr.group;
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
    # prowlarr-indexers fails on nixup before the stack is fully up;
    # apply it via `nixflix refresh` once everything is running.
    # seerr-setup is intentionally NOT disabled: it is idempotent (skips the
    # initial setup once Seerr reports initialized) and is what connects
    # Seerr to Jellyfin on every boot/nixup.
    prowlarr-indexers.enable = mkForce false;
    # Seerr overrides
    seerr = {
      serviceConfig.RestrictNamespaces = mkForce false;
      serviceConfig.ExecStartPre =
        let
          dataDir = config.nixflix.seerr.dataDir or "/data/.state/seerr";
        in
        lib.mkBefore "${pkgs.coreutils}/bin/mkdir -p ${dataDir}";
    };
    # Wait for Jellyfin before connecting Seerr to it (prevents 401 race)
    seerr-setup = {
      after = [ "jellyfin.service" ];
      wants = [ "jellyfin.service" ];
      serviceConfig.ExecStartPre = [
        (pkgs.writeShellScript "wait-jellyfin" ''
          echo "Waiting for Jellyfin API..."
          for i in $(seq 1 60); do
            if ${pkgs.curl.bin}/bin/curl -sf http://127.0.0.1:8096/System/Info/Public >/dev/null 2>&1; then
              echo "Jellyfin API ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "Timed out waiting for Jellyfin"
              exit 1
            fi
            sleep 2
          done
        '')
      ];
    };

    # Pre-write config.yaml with sops-managed API keys, providers, languages, and
    # quality/scan settings. Idempotent: rewrite when the file is missing OR any of
    # the critical integration patterns (sonarr: / radarr: blocks, providers,
    # pt-BR language) are absent. Covers the case where an earlier run wrote a
    # file with empty credentials because the secret was unreadable, or where the
    # file predates the auto-API-key integration. Provider credentials (e.g. the
    # OpenSubtitles.com API key) still need to be entered via the Bazarr UI.
    bazarr = {
      preStart =
        let
          bazarrApiKeyFile = config.sops.secrets."bazarr/api_key".path;
          sonarrApiKeyFile = config.sops.secrets."sonarr/api_key".path;
          radarrApiKeyFile = config.sops.secrets."radarr/api_key".path;
          sonarrPort = toString config.nixflix.sonarr.config.hostConfig.port;
          radarrPort = toString config.nixflix.radarr.config.hostConfig.port;
        in
        ''
          CONFIG_DIR=${config.services.bazarr.dataDir}/config
          CONFIG_FILE=$CONFIG_DIR/config.yaml
          mkdir -p "$CONFIG_DIR"

          BAZARR_API_KEY=$(cat ${bazarrApiKeyFile})
          SONARR_API_KEY=$(cat ${sonarrApiKeyFile})
          RADARR_API_KEY=$(cat ${radarrApiKeyFile})

          # Rewrite when integration credentials, providers, or languages are
          # missing. A healthy config has all of: apikey, sonarr:, radarr:,
          # enabled_providers, pt-BR, addic7ed, podnapisi, opensubtitles.
          needs_rewrite=0
          if [ ! -f "$CONFIG_FILE" ]; then
            needs_rewrite=1
          else
            for pattern in '^  apikey: \S' '^  sonarr:' '^  radarr:' '^  enabled_providers:' 'pt-BR' 'addic7ed' 'podnapisi' 'opensubtitles'; do
              if ! grep -qE "$pattern" "$CONFIG_FILE"; then
                needs_rewrite=1
                break
              fi
            done
          fi

          if [ "$needs_rewrite" -eq 1 ]; then
            cat > "$CONFIG_FILE" << EOF
          auth:
            apikey: $BAZARR_API_KEY
          general:
            use_sonarr: true
            use_radarr: true
            minimum_score: 90
            minimum_score_movie: 90
            use_postprocessing: true
            postprocessing_threshold: 90
            enabled_providers:
              - addic7ed
              - podnapisi
              - opensubtitles
          sonarr:
            ip: 127.0.0.1
            port: ${sonarrPort}
            base_url: /
            ssl: false
            apikey: $SONARR_API_KEY
            full_update: Daily
            full_update_hour: 3
          radarr:
            ip: 127.0.0.1
            port: ${radarrPort}
            base_url: /
            ssl: false
            apikey: $RADARR_API_KEY
            full_update: Daily
            full_update_hour: 3
          addic7ed:
            enabled: true
          podnapisi:
            enabled: true
          opensubtitles:
            enabled: true
          languages:
            enabled:
              - pt-BR
              - en
            profiles:
              - profileId: 1
                name: pt-BR + en
                cutoff: pt-BR
                items:
                  - language: pt-BR
                    audio_exclude: false
                    audio_only_include: false
                    forced: false
                    hi: false
                  - language: en
                    audio_exclude: false
                    audio_only_include: false
                    forced: false
                    hi: false
                mustContain: ""
                mustNotContain: ""
                originalFormat: null
                tag: ""
          EOF
            chown bazarr:${config.services.bazarr.group} "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            echo "Bazarr config.yaml regenerated with sops-managed credentials and declarative settings"
          else
            echo "Bazarr config.yaml already has integration credentials and providers, leaving alone"
          fi
        '';
    };

    # Bazarr setup: configures languages, providers, and quality settings via the Bazarr
    # API after the service is running. Uses form-encoded POST to /api/system/settings.
    # This is the mechanism that re-applies settings after nixflix full-refresh — the
    # preStart only writes config.yaml (bootstrap), but Bazarr stores languages/providers
    # in its database, so they must be set via API on subsequent runs.
    bazarr-setup = {
      description = "Configure Bazarr languages, providers, and quality settings via API";
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
        Restart = "on-failure";
        RestartSec = "10s";
        LoadCredential = [
          "bazarr_api_key:${config.sops.secrets."bazarr/api_key".path}"
        ];
      };

      script =
        let
          bazarrPort = toString config.services.bazarr.listenPort;
          curl = "${pkgs.curl.bin}/bin/curl";
        in
        ''
          set -eu

          BAZARR_API_KEY=$(cat /run/credentials/bazarr-setup.service/bazarr_api_key)
          BAZARR_URL="http://127.0.0.1:${bazarrPort}/api"

          echo "Waiting for Bazarr API..."
          for i in $(seq 1 60); do
            if ${curl} -sf "$BAZARR_URL/system/settings" \
              -H "X-Api-Key: $BAZARR_API_KEY" > /dev/null 2>&1; then
              echo "Bazarr API ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "Timed out waiting for Bazarr"
              exit 1
            fi
            sleep 2
          done

          echo "Configuring Bazarr languages, providers, and quality settings..."

          HTTP_CODE=$(${curl} -s -o /tmp/bazarr_setup_response -w "%{http_code}" \
            -X POST "$BAZARR_URL/system/settings" \
            -H "X-Api-Key: $BAZARR_API_KEY" \
            -d 'settings-general-use_sonarr=true' \
            -d 'settings-general-use_radarr=true' \
            -d 'settings-general-minimum_score=90' \
            -d 'settings-general-minimum_score_movie=90' \
            -d 'settings-general-use_postprocessing=true' \
            -d 'settings-general-postprocessing_threshold=90' \
            -d 'settings-general-serie_default_enabled=true' \
            -d 'settings-general-serie_default_profile=1' \
            -d 'settings-general-movie_default_enabled=true' \
            -d 'settings-general-movie_default_profile=1' \
            -d 'settings-general-enabled_providers=addic7ed' \
            -d 'settings-general-enabled_providers=podnapisi' \
            -d 'settings-general-enabled_providers=opensubtitles' \
            -d 'languages-enabled=pb' \
            -d 'languages-enabled=en' \
            -d 'languages-profiles=[{"profileId":1,"name":"pt-BR + en","cutoff":1,"items":[{"id":1,"language":"pb","audio_exclude":false,"audio_only_include":false,"forced":false,"hi":false},{"id":2,"language":"en","audio_exclude":false,"audio_only_include":false,"forced":false,"hi":false}],"mustContain":"","mustNotContain":"","originalFormat":null,"tag":""}]')

          if [ "$HTTP_CODE" -ge 400 ]; then
            echo "Bazarr setup failed (HTTP $HTTP_CODE):"
            cat /tmp/bazarr_setup_response
            exit 1
          fi

          echo "Bazarr languages, providers, and quality settings applied"
        '';
    };

    # Radarr → Jellyfin Connect notification: tells Jellyfin to refresh its library
    # whenever Radarr imports a movie. Mirrors Step 3 of the Jellyfin Full Automation
    # Guide (2026). Idempotent: matches by MediaBrowser implementation, creates if
    # missing, updates otherwise. The `updateLibrary` field is the actual library-
    # refresh trigger; `host`/`port`/`useSsl`/`urlBase` are the connection fields.
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
        LoadCredential = [
          "radarr_api_key:${
            if config.nixflix.radarr.config.apiKey._secret or null != null then
              config.nixflix.radarr.config.apiKey._secret
            else
              pkgs.writeText "radarr-api-key" config.nixflix.radarr.config.apiKey
          }"
          "jellyfin_api_key:${config.sops.secrets."jellyfin/api_key".path}"
        ];
      };
      script =
        let
          radarrPort = toString config.nixflix.radarr.config.hostConfig.port;
          jellyfinHost = "127.0.0.1";
          jellyfinPort = toString config.nixflix.jellyfin.network.internalHttpPort;
          curl = "${pkgs.curl.bin}/bin/curl";
          jq = "${pkgs.jq}/bin/jq";
        in
        ''
          set -eu

          RADARR_API_KEY=$(cat /run/credentials/radarr-jellyfin-connect.service/radarr_api_key)
          JELLYFIN_API_KEY=$(cat /run/credentials/radarr-jellyfin-connect.service/jellyfin_api_key)
          BASE_URL="http://127.0.0.1:${radarrPort}/api/v3"

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

          echo "Fetching notification schema for Emby / Jellyfin..."
          SCHEMAS=$(${curl} -s "$BASE_URL/notification/schema" -H "X-Api-Key: $RADARR_API_KEY")
          SCHEMA=$(echo "$SCHEMAS" | ${jq} -r --arg impl "Emby / Jellyfin" \
            '.[] | select(.implementationName == $impl) | @json' | head -n1)

          if [ -z "$SCHEMA" ] || [ "$SCHEMA" = "null" ]; then
            echo "Emby / Jellyfin notification schema not found in Radarr"
            exit 1
          fi

          echo "Fetching existing notifications..."
          EXISTING=$(${curl} -s "$BASE_URL/notification" -H "X-Api-Key: $RADARR_API_KEY")

          # Existing entries use implementation: "MediaBrowser", not the friendly name.
          EXISTING_ID=$(echo "$EXISTING" | ${jq} -r --arg impl MediaBrowser \
            '.[] | select(.implementation == $impl) | .id' | head -n1)

          # Build the notification payload from the schema. updateLibrary=true is
          # the actual "refresh Jellyfin library on import" trigger. Field names
          # are onMovieFileDelete / onMovieFileDeleteForUpgrade (no trailing 'd').
          NOTIFICATION=$(echo "$SCHEMA" | ${jq} \
            --arg host "${jellyfinHost}" \
            --argjson port ${jellyfinPort} \
            --arg apiKey "$JELLYFIN_API_KEY" \
            '
              .name = "Jellyfin"
              | .onGrab = false
              | .onDownload = true
              | .onUpgrade = true
              | .onRename = true
              | .onMovieAdded = true
              | .onMovieDelete = true
              | .onMovieFileDelete = true
              | .onMovieFileDeleteForUpgrade = true
              | .onHealthIssue = false
              | .onHealthRestored = false
              | .onApplicationUpdate = true
              | .onManualInteractionRequired = false
              | .includeHealthWarnings = false
              | .fields |= map(
                  if .name == "host" then .value = $host
                  elif .name == "port" then .value = $port
                  elif .name == "apiKey" then .value = $apiKey
                  elif .name == "useSsl" then .value = false
                  elif .name == "urlBase" then .value = ""
                  elif .name == "notify" then .value = false
                  elif .name == "updateLibrary" then .value = true
                  else . end
                )
            ')

          do_request() {
            local method="$1"
            local url="$2"
            ${curl} -s -o /tmp/req_response -w "%{http_code}" \
              -X "$method" "$url" \
              -H "X-Api-Key: $RADARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NOTIFICATION"
          }

          if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
            echo "Updating existing Radarr → Jellyfin notification (ID: $EXISTING_ID)..."
            HTTP_CODE=$(do_request PUT "$BASE_URL/notification/$EXISTING_ID")
          else
            echo "Creating Radarr → Jellyfin notification..."
            HTTP_CODE=$(do_request POST "$BASE_URL/notification")
          fi

          if [ "$HTTP_CODE" -ge 400 ]; then
            echo "Request failed (HTTP $HTTP_CODE):"
            cat /tmp/req_response
            exit 1
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
        LoadCredential = [
          "sonarr_api_key:${
            if config.nixflix.sonarr.config.apiKey._secret or null != null then
              config.nixflix.sonarr.config.apiKey._secret
            else
              pkgs.writeText "sonarr-api-key" config.nixflix.sonarr.config.apiKey
          }"
          "jellyfin_api_key:${config.sops.secrets."jellyfin/api_key".path}"
        ];
      };

      script =
        let
          sonarrPort = toString config.nixflix.sonarr.config.hostConfig.port;
          jellyfinHost = "127.0.0.1";
          jellyfinPort = toString config.nixflix.jellyfin.network.internalHttpPort;
          curl = "${pkgs.curl.bin}/bin/curl";
          jq = "${pkgs.jq}/bin/jq";
        in
        ''
          set -eu

          SONARR_API_KEY=$(cat /run/credentials/sonarr-jellyfin-connect.service/sonarr_api_key)
          JELLYFIN_API_KEY=$(cat /run/credentials/sonarr-jellyfin-connect.service/jellyfin_api_key)
          BASE_URL="http://127.0.0.1:${sonarrPort}/api/v3"

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

          echo "Fetching notification schema for Emby / Jellyfin..."
          SCHEMAS=$(${curl} -s "$BASE_URL/notification/schema" -H "X-Api-Key: $SONARR_API_KEY")
          SCHEMA=$(echo "$SCHEMAS" | ${jq} -r --arg impl "Emby / Jellyfin" \
            '.[] | select(.implementationName == $impl) | @json' | head -n1)

          if [ -z "$SCHEMA" ] || [ "$SCHEMA" = "null" ]; then
            echo "Emby / Jellyfin notification schema not found in Sonarr"
            exit 1
          fi

          echo "Fetching existing notifications..."
          EXISTING=$(${curl} -s "$BASE_URL/notification" -H "X-Api-Key: $SONARR_API_KEY")

          EXISTING_ID=$(echo "$EXISTING" | ${jq} -r --arg impl MediaBrowser \
            '.[] | select(.implementation == $impl) | .id' | head -n1)

          NOTIFICATION=$(echo "$SCHEMA" | ${jq} \
            --arg host "${jellyfinHost}" \
            --argjson port ${jellyfinPort} \
            --arg apiKey "$JELLYFIN_API_KEY" \
            '
              .name = "Jellyfin"
              | .onGrab = false
              | .onDownload = true
              | .onUpgrade = true
              | .onRename = true
              | .onSeriesAdd = true
              | .onSeriesDelete = true
              | .onEpisodeFileDelete = true
              | .onEpisodeFileDeleteForUpgrade = true
              | .onImportComplete = true
              | .onHealthIssue = false
              | .onHealthRestored = false
              | .onApplicationUpdate = true
              | .onManualInteractionRequired = false
              | .includeHealthWarnings = false
              | .fields |= map(
                  if .name == "host" then .value = $host
                  elif .name == "port" then .value = $port
                  elif .name == "apiKey" then .value = $apiKey
                  elif .name == "useSsl" then .value = false
                  elif .name == "urlBase" then .value = ""
                  elif .name == "notify" then .value = false
                  elif .name == "updateLibrary" then .value = true
                  else . end
                )
            ')

          do_request() {
            local method="$1"
            local url="$2"
            ${curl} -s -o /tmp/req_response -w "%{http_code}" \
              -X "$method" "$url" \
              -H "X-Api-Key: $SONARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NOTIFICATION"
          }

          if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
            echo "Updating existing Sonarr → Jellyfin notification (ID: $EXISTING_ID)..."
            HTTP_CODE=$(do_request PUT "$BASE_URL/notification/$EXISTING_ID")
          else
            echo "Creating Sonarr → Jellyfin notification..."
            HTTP_CODE=$(do_request POST "$BASE_URL/notification")
          fi

          if [ "$HTTP_CODE" -ge 400 ]; then
            echo "Request failed (HTTP $HTTP_CODE):"
            cat /tmp/req_response
            exit 1
          fi

          echo "Sonarr → Jellyfin Connect notification configured"
        '';
    };

    # Lidarr → Jellyfin Connect notification: same idea as Radarr/Sonarr's but for
    # artists/albums/tracks. Mirrors the Jellyfin Full Automation Guide (2026) so the
    # "Music" Jellyfin library auto-refreshes whenever Lidarr imports an album.
    # Lidarr uses the v1 API and different event-toggle names from Radarr/Sonarr
    # (onAlbumDownload / onAlbumAdded / onArtistAdd / onTrackFileDelete instead of
    # onMovieFileDelete / onSeriesAdd / onEpisodeFileDelete).
    lidarr-jellyfin-connect = mkIf config.nixflix.lidarr.enable {
      description = "Configure Lidarr Jellyfin Connect notification";
      after = [
        "lidarr.service"
        "lidarr-config.service"
        "network-online.target"
      ];
      requires = [ "lidarr.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";
        LoadCredential = [
          "lidarr_api_key:${
            if config.nixflix.lidarr.config.apiKey._secret or null != null then
              config.nixflix.lidarr.config.apiKey._secret
            else
              pkgs.writeText "lidarr-api-key" config.nixflix.lidarr.config.apiKey
          }"
          "jellyfin_api_key:${config.sops.secrets."jellyfin/api_key".path}"
        ];
      };

      script =
        let
          lidarrPort = toString config.nixflix.lidarr.config.hostConfig.port;
          jellyfinHost = "127.0.0.1";
          jellyfinPort = toString config.nixflix.jellyfin.network.internalHttpPort;
          curl = "${pkgs.curl.bin}/bin/curl";
          jq = "${pkgs.jq}/bin/jq";
        in
        ''
          set -eu

          LIDARR_API_KEY=$(cat /run/credentials/lidarr-jellyfin-connect.service/lidarr_api_key)
          JELLYFIN_API_KEY=$(cat /run/credentials/lidarr-jellyfin-connect.service/jellyfin_api_key)
          BASE_URL="http://127.0.0.1:${lidarrPort}/api/v1"

          echo "Waiting for Lidarr API..."
          for i in $(seq 1 60); do
            if ${curl} -sf "$BASE_URL/system/status" -H "X-Api-Key: $LIDARR_API_KEY" > /dev/null 2>&1; then
              echo "Lidarr API ready"
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "Timed out waiting for Lidarr"
              exit 1
            fi
            sleep 2
          done

          echo "Fetching notification schema for Emby / Jellyfin..."
          SCHEMAS=$(${curl} -s "$BASE_URL/notification/schema" -H "X-Api-Key: $LIDARR_API_KEY")
          SCHEMA=$(echo "$SCHEMAS" | ${jq} -r --arg impl "Emby / Jellyfin" \
            '.[] | select(.implementationName == $impl) | @json' | head -n1)

          if [ -z "$SCHEMA" ] || [ "$SCHEMA" = "null" ]; then
            echo "Emby / Jellyfin notification schema not found in Lidarr"
            exit 1
          fi

          echo "Fetching existing notifications..."
          EXISTING=$(${curl} -s "$BASE_URL/notification" -H "X-Api-Key: $LIDARR_API_KEY")

          EXISTING_ID=$(echo "$EXISTING" | ${jq} -r --arg impl MediaBrowser \
            '.[] | select(.implementation == $impl) | .id' | head -n1)

          NOTIFICATION=$(echo "$SCHEMA" | ${jq} \
            --arg host "${jellyfinHost}" \
            --argjson port ${jellyfinPort} \
            --arg apiKey "$JELLYFIN_API_KEY" \
            '
              .name = "Jellyfin"
              | .onGrab = false
              | .onDownload = true
              | .onUpgrade = true
              | .onRename = true
              | .onAlbumAdded = true
              | .onAlbumDownload = true
              | .onArtistAdd = true
              | .onArtistDelete = true
              | .onTrackFileDelete = true
              | .onTrackFileDeleteForUpgrade = true
              | .onImportComplete = true
              | .onHealthIssue = false
              | .onHealthRestored = false
              | .onApplicationUpdate = true
              | .onManualInteractionRequired = false
              | .includeHealthWarnings = false
              | .fields |= map(
                  if .name == "host" then .value = $host
                  elif .name == "port" then .value = $port
                  elif .name == "apiKey" then .value = $apiKey
                  elif .name == "useSsl" then .value = false
                  elif .name == "urlBase" then .value = ""
                  elif .name == "notify" then .value = false
                  elif .name == "updateLibrary" then .value = true
                  else . end
                )
            ')

          do_request() {
            local method="$1"
            local url="$2"
            ${curl} -s -o /tmp/req_response -w "%{http_code}" \
              -X "$method" "$url" \
              -H "X-Api-Key: $LIDARR_API_KEY" \
              -H "Content-Type: application/json" \
              -d "$NOTIFICATION"
          }

          if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
            echo "Updating existing Lidarr → Jellyfin notification (ID: $EXISTING_ID)..."
            HTTP_CODE=$(do_request PUT "$BASE_URL/notification/$EXISTING_ID")
          else
            echo "Creating Lidarr → Jellyfin notification..."
            HTTP_CODE=$(do_request POST "$BASE_URL/notification")
          fi

          if [ "$HTTP_CODE" -ge 400 ]; then
            echo "Request failed (HTTP $HTTP_CODE):"
            cat /tmp/req_response
            exit 1
          fi

          echo "Lidarr → Jellyfin Connect notification configured"
        '';
    };
  };
}
