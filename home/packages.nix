{
  pkgs,
  herdr,
  ...
}:
{
  nixpkgs.config.allowUnfree = true;

  # Rambox is managed out of band by `home/apps.nix` (it ships an
  # AppImage with a built-in self-updater that needs a writable path to
  # update, which the nixpkgs binary doesn't have).
  home.packages =
    with pkgs;
    [
      ggshield
      gnumake
      google-chrome
      helm
      helmfile
      jellyfin-desktop
      kubectl
      python3
      uv
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
