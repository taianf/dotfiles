{ pkgs, ... }: {
  programs = {
    nix-ld.enable = true;
    firefox.enable = true;
    zsh.enable = true;
    ssh.askPassword = pkgs.lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";

    # AppImage support: register binfmt_misc so AppImages can be executed
    # directly (e.g. `./Rambox.Appimage` instead of `appimage-run Rambox.Appimage`),
    # and inject extra libraries for AppImages that need them. Some apps
    # (Rambox, others) ship their own old glibc and break on modern NixOS;
    # the override below makes `appimage-run`'s FHS env see the same icu /
    # libxcrypt-legacy / Python+PyTorch versions the upstream build expects.
    appimage = {
      enable = true;
      binfmt = true;
      package = pkgs.appimage-run.override {
        extraPkgs = pkgs: [
          pkgs.icu
          pkgs.libxcrypt-legacy
          pkgs.python312
          pkgs.python312Packages.torch
        ];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    jq
    nh
    nil
    nixd
    prek
    nixfmt
    sops
    statix
    wget
  ];
}
