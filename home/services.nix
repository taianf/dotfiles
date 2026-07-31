{
  config,
  pkgs,
  ferdiumWrapped,
  ramboxWrapped,
  ...
}:
{
  systemd.user.services.dotfiles-sync = {
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

  systemd.user.services.ferdium = {
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

  systemd.user.services.rambox = {
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
      ExecStart = "${ramboxWrapped}/bin/rambox";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
