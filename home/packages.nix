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
      nil
      opencode-desktop
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
