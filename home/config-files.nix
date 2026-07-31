_: {
  xdg.configFile = {
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
    "opencode/opencode.json" = {
      force = true;
      source = ../config/opencode/opencode.json;
    };
    "opencode/opencode.jsonc" = {
      force = true;
      source = ../config/opencode/opencode.jsonc;
    };
    "opencode/package.json".source = ../config/opencode/package.json;
    "opencode/plugins/herdr-agent-state.js".source = ../config/opencode/plugins/herdr-agent-state.js;
    "opencode/tui.json" = {
      force = true;
      source = ../config/opencode/tui.json;
    };
    "topgrade.toml".source = ../config/topgrade.toml;
  };
}
