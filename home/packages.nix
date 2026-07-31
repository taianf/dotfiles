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
      python3
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
