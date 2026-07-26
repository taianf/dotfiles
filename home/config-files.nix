_: {
  xdg.configFile = {
    "autostart/ferdium.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Ferdium
      Exec=ferdium
      X-GNOME-Autostart-enabled=true
    '';
    "autostart/opencode-desktop.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=OpenCode Desktop
      Exec=opencode-desktop
      X-GNOME-Autostart-enabled=true
    '';
    "cosmic/com.system76.CosmicComp/v1/keyboard_config" = {
      force = true;
      text = ''
        (
            numlock_state: BootOn,
        )
      '';
    };
    "zed/settings.json".source = ../config/zed/settings.json;
    "topgrade.toml".source = ../config/topgrade.toml;
    "opencode/opencode.json".source = ../config/opencode/opencode.json;
  };
}
