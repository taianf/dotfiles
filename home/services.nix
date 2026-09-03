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
  };
}
