# Shared NixOS configuration — import this from any machine's configuration.nix
{pkgs, ...}: {
  # Locale & timezone
  time.timeZone = "Europe/Lisbon";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_PT.UTF-8";
    LC_IDENTIFICATION = "pt_PT.UTF-8";
    LC_MEASUREMENT = "pt_PT.UTF-8";
    LC_MONETARY = "pt_PT.UTF-8";
    LC_NAME = "pt_PT.UTF-8";
    LC_NUMERIC = "pt_PT.UTF-8";
    LC_PAPER = "pt_PT.UTF-8";
    LC_TELEPHONE = "pt_PT.UTF-8";
    LC_TIME = "pt_PT.UTF-8";
  };

  # Console keymap
  console.keyMap = "dvorak";

  # Desktop — X11 + GNOME
  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "alt-intl";
      };
    };
    displayManager = {
      defaultSession = "plasma";
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
  };

  # Programs
  programs = {
    nix-ld.enable = true;
    firefox.enable = true;
    zsh.enable = true;
    ssh.askPassword = pkgs.lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
  };

  # DDC/CI monitor control
  hardware.i2c.enable = true;

  environment.systemPackages = with pkgs; [
    ddcutil
    ddcui
    wl-clipboard
    xclip
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable all terminfo entries
  environment.enableAllTerminfo = true;

  # User account
  users.users."taian" = {
    isNormalUser = true;
    description = "Taian Fonseca Feitosa";
    extraGroups = [
      "i2c"
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
  };
}
