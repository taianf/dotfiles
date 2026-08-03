{
  pkgs,
  herdr,
  ...
}:
let
  # helmfile's `diff` subcommand shells out to `helm diff upgrade`,
  # which the base `kubernetes-helm` package doesn't ship. Wrap
  # helm with the helm-diff plugin, and tell helmfile-wrapped
  # where to find the wrapped helm's plugins. Per
  # https://wiki.nixos.org/wiki/Helm_and_Helmfile.
  myHelm = pkgs.wrapHelm pkgs.kubernetes-helm {
    plugins = [ pkgs.kubernetes-helmPlugins.helm-diff ];
  };
  myHelmfile = pkgs.helmfile-wrapped.override {
    inherit (myHelm) pluginsDir;
  };
in
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
      myHelm
      myHelmfile
      jellyfin-desktop
      kubectl
      python3
      uv
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
