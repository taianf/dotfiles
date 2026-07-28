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
    "opencode/.gitignore".source = ../config/opencode/.gitignore;
    "opencode/command".source = ../config/opencode/command;
    "opencode/oh-my-opencode-slim.json".source = ../config/opencode/oh-my-opencode-slim.json;
    "opencode/opencode.json".source = ../config/opencode/opencode.json;
    "opencode/opencode.jsonc".source = ../config/opencode/opencode.jsonc;
    "opencode/oh-my-openagent.json".source = ../config/opencode/oh-my-openagent.json;
    "opencode/package.json".source = ../config/opencode/package.json;
    "opencode/plugins/herdr-agent-state.js".source = ../config/opencode/plugins/herdr-agent-state.js;
    "opencode/tui.json".source = ../config/opencode/tui.json;
    "topgrade.toml".source = ../config/topgrade.toml;
  };
}
