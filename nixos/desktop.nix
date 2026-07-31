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
}
