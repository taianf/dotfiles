# Nixflix — media server stack (Sonarr, Radarr, Jellyfin, etc.)
{ config, ... }:

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
    "sabnzbd/api_key" = { };
    "sabnzbd/nzb_key" = { };
    "sabnzbd/username" = { };
    "sabnzbd/password" = { };
    "jellyfin/api_key" = { };
    "jellyfin/admin_password" = { };
    "seerr/api_key" = { };
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
          { name = "Nzbl"; }
          { name = "SimplyNZBs"; }
          { name = "NZBIndex"; }
        ];
      };
    };

    usenetClients.sabnzbd = {
      enable = true;
      settings = {
        misc = {
          api_key._secret = config.sops.secrets."sabnzbd/api_key".path;
          nzb_key._secret = config.sops.secrets."sabnzbd/nzb_key".path;
          username._secret = config.sops.secrets."sabnzbd/username".path;
          password._secret = config.sops.secrets."sabnzbd/password".path;
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
  };
}
