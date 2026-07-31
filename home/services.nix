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

    # Both apps are managed by `home/apps.nix` (AppImage + wrapper in
    # ~/.local/bin). The wrappers pass the Wayland flags that the old
    # `*Wrapped` symlinkJoin derivations used to add, so the
    # fractional-scaled render stays crisp.
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
        ExecStart = "${appsDir}/ferdium";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

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
