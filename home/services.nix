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
        # `--hidden` makes the AppImage start in the tray instead of
        # showing a window (Rambox checks argv for the substring "hidden"
        # in its Electron main process). Necessary because home-manager
        # re-evaluates the user systemd unit on every `nixup` and the
        # regenerated symlink target causes a `try-restart` — each
        # restart kills the running Rambox and spawns a new one, which
        # would otherwise pop a window in the user's face. Manual
        # launches from the app launcher still see a window (the .desktop
        # `Exec=rambox %U` doesn't pass `--hidden`).
        ExecStart = "${appsDir}/rambox --hidden";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
