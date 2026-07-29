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
      prek
      nixfmt
      python3
      sops
      statix
      uv
      wget
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
