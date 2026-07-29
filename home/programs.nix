{
  pkgs,
  ...
}:
{
  programs = {
    ghostty = {
      enable = true;
      enableZshIntegration = true;
    };
    opencode.enable = true;
    gh.enable = true;
    topgrade.enable = true;
    spotify-player.enable = true;
    bun.enable = true;
    fzf.enable = true;

    zsh = {
      enable = true;
      oh-my-zsh = {
        enable = true;
        theme = "robbyrussell";
        plugins = [
          "autojump"
          "brew"
          "copybuffer"
          "copyfile"
          "dirhistory"
          "dotenv"
          "git"
          "sudo"
          "web-search"
        ];
      };
      plugins = [
        {
          name = "zsh-autosuggestions";
          src = pkgs.zsh-autosuggestions;
          file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
        }
        {
          name = "zsh-syntax-highlighting";
          src = pkgs.zsh-syntax-highlighting;
          file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
        }
      ];
      initContent = ''
        export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
        export PATH="$HOME/dotfiles/bin:$HOME/.bun/bin:$PATH"
        source $HOME/dotfiles/zsh/completions/_nixflix 2>/dev/null
        eval "$(COMPLETE=zsh prek)"

        docker() {
          if [ "$1" = "compose" ]; then
            shift
            command podman compose "$@"
          else
            command podman "$@"
          fi
        }
      '';
    };

    git = {
      enable = true;
      settings.user.name = "Taian Fonseca Feitosa";
      settings.user.email = "taian.f.feitosa@gmail.com";
    };

    zed-editor = {
      enable = true;
      mutableUserSettings = true;
      extensions = [ "nix" ];
      userSettings = {
        format_on_save = "on";
        autosave = "on_focus_change";
        git_panel = {
          tree_view = true;
        };
        diff_view_style = "unified";
        project_panel = {
          dock = "left";
        };
        agent_servers = {
          kilo = {
            type = "registry";
          };
          opencode = {
            default_config_options = {
              model = "opencode/deepseek-v4-flash-free";
            };
            type = "registry";
          };
        };
        cli_default_open_behavior = "existing_window";
        agent = {
          tool_permissions = {
            tools = {
              fetch = {
                default = "allow";
              };
              terminal = {
                default = "allow";
                always_allow = [
                  {
                    pattern = "^cat\\s+\\~/\\.config/zed/settings\\.json(\\s|$)";
                  }
                  {
                    pattern = "^wc\\b";
                  }
                  {
                    pattern = "^nix\\s+search(\\s|$)";
                  }
                  {
                    pattern = "^head\\b";
                  }
                  {
                    pattern = "^echo\\b";
                  }
                  {
                    pattern = "^grep\\b";
                  }
                  {
                    pattern = "^which\\s+age-keygen(\\s|$)";
                  }
                  {
                    pattern = "^which\\s+age(\\s|$)";
                  }
                  {
                    pattern = "^which\\s+sops(\\s|$)";
                  }
                  {
                    pattern = "^ls\\s+/etc/age/(\\s|$)";
                  }
                  {
                    pattern = "^ls\\s+\\~/\\.config/sops/age/(\\s|$)";
                  }
                  {
                    pattern = "^nix-shell\\b";
                  }
                ];
              };
            };
          };
          default_model = {
            provider = "opencode";
            model = "free/big-pickle";
            enable_thinking = false;
          };
          favorite_models = [
            {
              provider = "openrouter";
              model = "openrouter/free";
              enable_thinking = true;
            }
            {
              provider = "openrouter";
              model = "openrouter/auto";
              enable_thinking = true;
            }
            {
              provider = "openrouter";
              model = "openrouter/auto-beta";
              enable_thinking = true;
            }
            {
              provider = "opencode";
              model = "free/big-pickle";
              enable_thinking = false;
            }
          ];
          model_parameters = [ ];
        };
        lsp = {
          ruff = {
            settings = {
              select = [ "I" ];
              lint = {
                select = [ "I" ];
              };
            };
          };
          pyright = {
            settings = { };
          };
        };
        languages = {
          Python = {
            language_servers = [
              "!basedpyright"
              "ruff"
              "..."
            ];
          };
        };
        code_actions_on_format = {
          "source.fixAll.ruff" = true;
          "source.organizeImports.ruff" = true;
        };
        ui_font_size = 16;
        buffer_font_size = 15;
        theme = {
          mode = "system";
          light = "One Light";
          dark = "One Dark";
        };
        terminal = {
          shell = {
            program = "/home/taian/.nix-profile/bin/zsh";
          };
        };
      };
    };
  };

  # Required for the `autojump` oh-my-zsh plugin: the plugin shells out
  # to the `autojump` binary, which lives in the `programs.autojump`
  # package. Without this, every new zsh prints
  # `[oh-my-zsh] autojump not found. Please install it first.`
  programs.autojump.enable = true;

  # Required for `codegraph` (Bun global install) whose launcher has
  # `#!/usr/bin/env node`. Without this, `codegraph` errors with
  # `env: 'node': No such file or directory`.
  #
  # The pinned `home-manager` (see `flake.lock`) does not yet expose a
  # `programs.nodejs` module, so we install the package directly at
  # the top level. When a newer `home-manager` is bumped in, switch
  # back to `programs.nodejs.enable = true;` per AGENTS.md (prefer
  # `programs.*` over `home.packages`).
  home.packages = [ pkgs.nodejs ];
}
