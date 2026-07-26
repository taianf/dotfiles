{ pkgs, ... }: {
  hardware.i2c.enable = true;

  environment.systemPackages = with pkgs; [
    ddcutil
    ddcui
    wl-clipboard
    xclip
  ];

  nixpkgs.config.allowUnfree = true;

  environment.enableAllTerminfo = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
}
