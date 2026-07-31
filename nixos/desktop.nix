{ pkgs, ... }: {
  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "alt-intl";
      };
    };
    displayManager = {
      defaultSession = "cosmic";
      cosmic-greeter.enable = true;
    };
    desktopManager = {
      gnome.enable = true;
      cosmic.enable = true;
      plasma6.enable = true;
    };
    system76-scheduler.enable = true;
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    printing.enable = true;
    openssh.enable = true;
    flatpak = {
      enable = true;

      # Declarative remotes + apps, provided by the
      # `in-a-dil-emma/declarative-flatpak` module (imported from
      # `flake.nix` and wired in `nixos/configuration.nix`). The
      # upstream NixOS `services.flatpak` module only ships
      # `enable` + `package`; this third-party module extends the same
      # `services.flatpak.*` namespace with `remotes` and `packages`
      # (and a transactional systemd service that runs at boot to
      # reconcile the install against the declared set). The
      # `flathub:` prefix on each package disambiguates when more
      # remotes are added later.
      remotes = {
        "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      };

      # Fladder: KDE/Qt media player for the *arr stack (Sonarr/Radarr
      # libraries, Jellyfin-style browsing). The module installs it at
      # the system level (`/var/lib/flatpak/`) which the upstream
      # `services.flatpak` module already exports via `XDG_DATA_DIRS`
      # /PAM, so desktop entries appear without the
      # "exports/share not in XDG_DATA_DIRS" warning the user-level
      # `flatpak` binary prints.
      packages = [
        "flathub:app/nl.jknaapen.fladder//stable"
      ];
    };

    # Keep the host available on the network (Jellyfin streams, SSH, etc.) —
    # never suspend or hibernate on idle or lid close. The display can still
    # blank via DPMS / GNOME power settings; this only disables the
    # system-wide sleep triggers owned by systemd-logind.
    logind.settings.Login = {
      IdleAction = "ignore";
      HandleLidSwitch = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };
  };
}
