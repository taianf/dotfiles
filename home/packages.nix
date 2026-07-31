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
      jq
      nh
      nil
      nixd
      prek
      nixfmt
      python3
      sops
      statix
      wget
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
