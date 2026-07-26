{
  pkgs,
  herdr,
  ...
}:
{
  nixpkgs.config.allowUnfree = true;

  home.packages =
    with pkgs;
    [
      (pkgs.symlinkJoin {
        name = "ferdium-wrapped";
        paths = [ pkgs.ferdium ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/ferdium \
            --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations" \
            --add-flags "--ozone-platform=wayland"
        '';
      })
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
      zed-editor
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
