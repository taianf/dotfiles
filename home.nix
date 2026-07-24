{
  config,
  pkgs,
  herdr,
  ...
}:

{

  nixpkgs.config.allowUnfree = true;

  home = {
    stateVersion = "23.11";
    homeDirectory = "/home/taian";
    username = "taian";

    packages =
      with pkgs;
      [
        ferdium
        google-chrome
        nil
        nixd
        nixfmt
        python3
        sops
        statix
        uv
        wget
        zed-editor
      ]
      ++ [
        herdr.packages.${system}.default
      ];
  };

  xdg.configFile = {
    "zed/settings.json".source = ./config/zed/settings.json;
    "topgrade.toml".source = ./config/topgrade.toml;
    "opencode/opencode.json".source = ./config/opencode/opencode.json;
  };

  programs = {
    ghostty = {
      enable = true;
      enableZshIntegration = true;
    };
    opencode.enable = true;
    gh.enable = true;
    topgrade.enable = true;

    zsh = {
      enable = true;
      oh-my-zsh = {
        enable = true;
        theme = "robbyrussell";
        plugins = [
          "git"
          "sudo"
        ];
      };
      initContent = ''
        export PATH="$HOME/dotfiles/bin:$PATH"

        # Rebuild both NixOS and Home Manager
        nixup() {
          local log
          if [ "$1" = "--dry-run" ]; then
            echo "==> Checking flake..."
            nix flake check ~/dotfiles && echo "✓ flake check passed"
            echo "==> Parsing nix files..."
            for f in ~/dotfiles/*.nix ~/dotfiles/nixos/*.nix; do
              nix-instantiate --parse "$f" > /dev/null && echo "✓ $f"
            done
            return 0
          elif [ "$1" = "--verbose" ]; then
            sudo nixos-rebuild switch && \
            nix run home-manager -- -v init --switch ~/dotfiles
          else
            log=$(sudo nixos-rebuild switch --quiet 2>&1) || {
              echo "$log"
              return 1
            }
            log=$(nix run home-manager -- init --switch ~/dotfiles 2>&1) || {
              echo "$log"
              return 1
            }
          fi
        }
      '';
    };

    git = {
      enable = true;
      settings.user.name = "Taian Fonseca Feitosa";
      settings.user.email = "taian.f.feitosa@gmail.com";
    };
  };

  # Use a systemd service to pull the latest dotfiles on each boot
  systemd.user.services.dotfiles-sync = {
    Unit = {
      Description = "Sync dotfiles from Git";
      After = [ "network-online.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.git}/bin/git -C ${config.home.homeDirectory}/dotfiles pull origin main
      '';
    };
  };

}
