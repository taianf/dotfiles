{
  pkgs,
  herdr,
  ...
}:
{
  nixpkgs.config.allowUnfree = true;

  # Rambox and Ferdium are managed out of band by `home/apps.nix` (they
  # ship AppImages with built-in self-updaters that need a writable path
  # to update, which the nixpkgs binaries don't have).
  home.packages =
    with pkgs;
    [
      ggshield
      google-chrome
      jellyfin-desktop
      python3
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
