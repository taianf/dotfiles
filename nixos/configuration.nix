# Machine-specific configuration — lives in ~/dotfiles, symlinked to /etc/nixos/
# On new machines: sudo ln -sf ~/dotfiles/nixos/configuration.nix /etc/nixos/configuration.nix
{ vpn-confinement, pkgs, ... }:
{
  imports = [
    /etc/nixos/hardware-configuration.nix
    "${vpn-confinement}/modules/vpn-netns.nix"
    ./default.nix
    ./nvidia.nix
    ./cachyos-kernel.nix
    ./p275mv-plus.nix
    ./k3s.nix
  ];

  # k3s single-node cluster for the *arr media stack. See ./k3s.nix for
  # the rationale on port 30080/30443 + the side-by-side cutover. Set
  # `ingressForward = true` after nixflix is removed to drop the
  # `:30080` port suffix from the *arr URLs.
  services.k3s-servarr.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "taian-nix";
  networking.networkmanager.enable = true;

  system.stateVersion = "26.05";

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [
      "https://cache.nixos.org"
      "https://attic.xuyh0120.win/lantian"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    ];
    max-jobs = pkgs.lib.mkDefault (
      builtins.div (builtins.fromJSON (builtins.readFile (pkgs.runCommand "nproc" { } "nproc > $out"))) 2
    );
  };
}
