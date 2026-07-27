_: {
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
        export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
        export PATH="$HOME/dotfiles/bin:$PATH"
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
            sudo nixos-rebuild switch --impure --flake ~/dotfiles#nixos && \
            nix run home-manager -- -v init --switch ~/dotfiles -b backup
          else
            log=$(sudo nixos-rebuild switch --impure --quiet --flake ~/dotfiles#nixos 2>&1) || {
              echo "$log"
              return 1
            }
            log=$(nix run home-manager -- init --switch ~/dotfiles -b backup 2>&1) || {
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
}
