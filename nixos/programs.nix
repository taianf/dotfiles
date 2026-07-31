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

    # Expose `libfuse.so.2` (FUSE 2) on the nix-ld library path. AppManager
    # (and other AppImages) detect FUSE support by dlopen("libfuse.so.2") and
    # by `fusermount` on PATH. `programs.fuse.enable` (pulled in via
    # `programs.appimage.enable` above) already puts `fusermount` in PATH and
    # `pkgs.fuse` in `environment.systemPackages`, but the lib lives in
    # `/run/current-system/sw/lib/` which the dynamic linker does not search
    # for unpatched binaries like AppImages. nix-ld's `libraries` symlinks
    # each package's `lib/` into `/share/nix-ld/lib/` and exports
    # `NIX_LD_LIBRARY_PATH` globally via `environment.sessionVariables`,
    # making `libfuse.so.2` findable system-wide — and silences AppManager's
    # "FUSE is not installed" banner (which is just a false negative caused
    # by that missing link).
    nix-ld.libraries = [ pkgs.fuse ];
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
