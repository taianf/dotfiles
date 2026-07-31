{
  pkgs,
  herdr,
  ferdiumWrapped,
  ramboxWrapped,
  ...
}:
{
  nixpkgs.config.allowUnfree = true;

  home.packages =
    with pkgs;
    [
      ferdiumWrapped
      ramboxWrapped
      ggshield
      google-chrome
      jellyfin-desktop
      python3
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
