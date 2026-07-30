{
  config,
  pkgs,
  ferdiumWrapped,
  ...
}:
let
  home = config.home.homeDirectory;
in
{
  # See SYNC.md for the live -> repo / repo -> live model.
  systemd.user = {
    # Auto-sync (live -> repo): a systemd path unit watches ~/.config
    # for changes and triggers bin/sync-dotfiles. Each save in any
    # program results in a commit within seconds. Push is best-effort.
    paths.dotfiles-sync = {
      Unit = {
        Description = "Watch ~/.config for changes to trigger sync-dotfiles";
      };
      Path = {
        PathChanged = [
          "${home}/.config"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    services = {
      dotfiles-sync = {
        Unit = {
          Description = "Mirror live dotfiles to the repo and commit";
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${home}/dotfiles/bin/sync-dotfiles";
        };
      };

      # Additive boot pull (repo -> live): pull main, then deploy any
      # NEW files (where live is missing) to ~/.config. NEVER
      # overwrites an existing live file — live wins. The "new config
      # in a commit shows up on next boot" half.
      dotfiles-sync-on-boot = {
        Unit = {
          Description = "Pull main and deploy new config files to live (additive)";
          After = [ "network-online.target" ];
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${home}/dotfiles/bin/sync-dotfiles-on-boot";
        };
      };

      ferdium = {
        Unit = {
          Description = "Ferdium messaging client";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${ferdiumWrapped}/bin/ferdium";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    };
  };
}
