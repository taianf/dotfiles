{
  pkgs,
  herdr,
  kilocode,
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

  # helmfile passes --timeout=10m to `helm diff upgrade` (set in
  # the servarr workspace's helmDefaults.args). helm-diff doesn't
  # recognize that flag — it's a `helm upgrade` flag, not a
  # helm-diff one. Set the standard helm-diff passthrough env var
  # so unknown flags flow through to helm instead of erroring.
  # See https://github.com/databus23/helm-diff/issues/278.
  home.sessionVariables = {
    HELM_DIFF_IGNORE_UNKNOWN_FLAGS = "true";
  };

  # Rambox is managed out of band by `home/apps.nix` (it ships an
  # AppImage with a built-in self-updater that needs a writable path to
  # update, which the nixpkgs binary doesn't have).
  home.packages =
    with pkgs;
    [
      ggshield
      gnumake
      google-chrome
      k9s
      myHelm
      myHelmfile
      jellyfin-desktop
      kubectl
      python3
      uv
      nur.packages.${pkgs.system}.waydroid-script
    ]
    ++ [
      herdr.packages.${pkgs.system}.default
    ];
}
