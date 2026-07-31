{ pkgs, ... }: {
  programs = {
    nix-ld.enable = true;
    firefox.enable = true;
    zsh.enable = true;
    ssh.askPassword = pkgs.lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };

  environment.systemPackages = with pkgs; [
    jq
    nh
    nil
    nixd
    prek
    nixfmt
    sops
    statix
    wget
  ];
}
