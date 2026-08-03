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
      # Note: not `helm` — that's a polyphonic synthesizer
      # (https://tytel.org/helm) that occupies the same name in
      # nixpkgs. The Kubernetes package manager is `kubernetes-helm`.
      kubernetes-helm
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
