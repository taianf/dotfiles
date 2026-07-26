# Shared NixOS configuration — import this from any machine's configuration.nix
{ ... }: {
  imports = [
    ./locale.nix
    ./desktop.nix
    ./programs.nix
    ./hardware.nix
    ./users.nix
  ];

}
