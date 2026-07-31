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
    flatpak.enable = true;

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

  # The pinned nixpkgs's `services.flatpak` module is daemon-only
  # (`enable` + `package`); it does not expose declarative `remotes` or
  # `packages`. Manage the flathub remote + fladder install via an
  # activation script instead. Runs as root at switch time, so flatpak
  # installs land at the system level (`/var/lib/flatpak/`) — the same
  # path the module exports via `XDG_DATA_DIRS`/PAM, so desktop entries
  # appear without the "exports/share not in XDG_DATA_DIRS" warning
  # the user-level `flatpak` binary prints.
  system.activationScripts.flatpak = {
    text = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists \
        flathub https://dl.flathub.org/repo/flathub.flatpakrepo

      # Skip if fladder is already present at either system or user
      # level — `flatpak list` shows both, so a pre-existing user-level
      # install (e.g. one done imperatively before this was wired up)
      # also satisfies the guard.
      if ! ${pkgs.flatpak}/bin/flatpak list --app 2>/dev/null \
          | grep -q nl.jknaapen.fladder; then
        ${pkgs.flatpak}/bin/flatpak install --noninteractive --assumeyes \
          flathub nl.jknaapen.fladder
      fi
    '';
  };
}
