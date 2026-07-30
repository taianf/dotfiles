{
  pkgs,
  herdr,
  ferdiumWrapped,
  ...
}:
{
  nixpkgs.config.allowUnfree = true;

  home.packages =
    with pkgs;
    [
      ferdiumWrapped
      ggshield
      google-chrome
      jq
      nh
      nil
      nixd
      nixfmt
      prek
      python3
      sops
      statix
      wget
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
