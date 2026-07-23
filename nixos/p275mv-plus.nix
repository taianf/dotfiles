# Declarative DDC/CI monitor settings — BenQ P275MV Plus
{ config, pkgs, ... }:

let
  monitorSettings = {
    bus = 16;
    brightness = 80;
  };

  applyScript = pkgs.writeShellScript "apply-monitor" ''
    export HOME="/root"
    ${pkgs.ddcutil}/bin/ddcutil --bus ${toString monitorSettings.bus} --noverify setvcp 10 ${toString monitorSettings.brightness}
  '';
in
{
  systemd.services.apply-monitor = {
    description = "Apply DDC/CI monitor settings";
    after = [ "display-manager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${applyScript}";
    };
  };
}
