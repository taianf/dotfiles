# Machine-specific configuration — lives in ~/dotfiles, symlinked to /etc/nixos/
# On new machines: sudo ln -sf ~/dotfiles/nixos/configuration.nix /etc/nixos/configuration.nix
{ config, pkgs, ... }:

let
  sops-nix = builtins.fetchTarball "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
  nixflix = builtins.fetchTarball "https://github.com/kiriwalawren/nixflix/archive/main.tar.gz";
in
{
  imports = [
    "${nixflix}/nixosModules/default.nix"
    "${sops-nix}/modules/sops-nix.nix"
    ./default.nix
    ./nixflix.nix
    ./nvidia.nix
    ./sops.nix
    /etc/nixos/hardware-configuration.nix
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Machine hostname — change per machine
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  system.stateVersion = "26.05";
}
