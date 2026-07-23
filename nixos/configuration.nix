# Machine-specific configuration — lives in ~/dotfiles, symlinked to /etc/nixos/
# On new machines: sudo ln -sf ~/dotfiles/nixos/configuration.nix /etc/nixos/configuration.nix
_:

let
  sops-nix = builtins.fetchTarball "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
  nixflix = builtins.fetchTarball "https://github.com/kiriwalawren/nixflix/archive/master.tar.gz";
  vpn-confinement = builtins.fetchTarball "https://github.com/Maroka-chan/VPN-Confinement/archive/master.tar.gz";
in
{
  imports = [
    /etc/nixos/hardware-configuration.nix
    "${nixflix}/modules/default.nix"
    "${sops-nix}/modules/sops/default.nix"
    "${vpn-confinement}/modules/vpn-netns.nix"
    ./default.nix
    ./nixflix
    ./nvidia.nix
    ./p275mv-plus.nix
    ./sops.nix
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Machine hostname — change per machine
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  system.stateVersion = "26.05";
}
