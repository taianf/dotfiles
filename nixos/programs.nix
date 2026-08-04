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
    gnome-software
    jq
    nh
    nil
    nixd
    nixfmt
    prek
    sops
    statix
    wget
  ];

  # Share the sudo credential cache across every TTY so non-interactive
  # subprocesses (AI agents, scripts, hook-driven tooling) can use a
  # `sudo -v` the user typed into an interactive terminal. Default
  # behavior is per-TTY, which makes every TTY in a subshell prompt
  # for the password — incompatible with bash invocations from a
  # coding agent that has no PTY. The 10-minute default timestamp
  # timeout is unchanged. See https://www.dgt.is/blog/2026-03-10-ai-sudo-with-agents/
  # for the matching agent-side helper. Security note: any local
  # process can use the cached creds during the timeout window;
  # this is appropriate for a personal dev machine, NOT for shared
  # systems (use NOPASSWD per-command or polkit there).
  security.sudo.extraConfig = "Defaults timestamp_type=global";
}
