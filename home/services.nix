{
  config,
  pkgs,
  ...
}:
let
  appsDir = "${config.home.homeDirectory}/.local/bin";
in
{
  systemd.user.services = {
    dotfiles-sync = {
      Unit = {
        Description = "Sync dotfiles from Git";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = ''
          ${pkgs.git}/bin/git -C ${config.home.homeDirectory}/dotfiles pull origin main
        '';
      };
    };

    # Rambox is managed by `home/apps.nix` (AppImage + wrapper in
    # ~/.local/bin). The wrapper passes the Wayland flags that the old
    # `*Wrapped` symlinkJoin derivations used to add, so the
    # fractional-scaled render stays crisp.
    rambox = {
      Unit = {
        Description = "Rambox messaging client";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${appsDir}/rambox";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
