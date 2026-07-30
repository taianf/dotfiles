{
  pkgs,
  lib,
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

    uv = {
      enable = true;
      settings = {
        # On NixOS, system Python is provided by nixpkgs. Don't let uv
        # auto-download its own interpreter (which would land in
        # ~/.local/share/uv/python and bypass the Nix store); prefer
        # system Python for `uv run` etc.
        python-downloads = "never";
        python-preference = "only-system";
      };
    };

    # Installs `pkgs.nodejs` (node + npm + npx + corepack) via the
    # `programs.npm` module. Required by the codegraph activation block
    # below — its `#!/usr/bin/env node` launcher needs `node` on PATH.
    npm = {
      enable = true;
      settings = {
        # Keep npm's global prefix inside HOME, not /usr, so `npm i -g`
        # doesn't touch the immutable Nix store.
        prefix = "\${HOME}/.npm-global";
      };
    };

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
      # initContent is intentionally empty: the actual ~/.zshrc content
      # lives in config/zsh/.zshrc and is seeded/copied via
      # home.activation.seed-dotfiles (see below). Editing ~./.zshrc in
      # place is the supported workflow; the systemd path unit
      # auto-mirrors the change back to the repo. See SYNC.md.
    };

    git = {
      enable = true;
      settings.user.name = "Taian Fonseca Feitosa";
      settings.user.email = "taian.f.feitosa@gmail.com";
    };

    zed-editor = {
      enable = true;
      extensions = [ "nix" ];
      # The user-editable settings live in config/zed/settings.json and
      # are seeded to ~/.config/zed/settings.json by
      # home.activation.seed-dotfiles (see below). We deliberately do
      # NOT set `userSettings` or `mutableUserSettings` here: the file
      # is fully owned by the user, with the repo as a mirror. See SYNC.md.
    };
  };

  # Required for the `autojump` oh-my-zsh plugin: the plugin shells out
  # to the `autojump` binary, which lives in the `programs.autojump`
  # package. Without this, every new zsh prints
  # `[oh-my-zsh] autojump not found. Please install it first.`
  programs.autojump.enable = true;

  # CodeGraph: semantic code intelligence CLI / MCP server
  # (https://github.com/colbymchenry/codegraph). Installed as a bun
  # global after the first `home-manager switch` so the `codegraph`
  # binary is on PATH and the opencode MCP entry below resolves.
  home.activation.codegraph = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v codegraph >/dev/null 2>&1; then
      ${pkgs.bun}/bin/bun add -g @colbymchenry/codegraph
    fi
  '';

  # First-install (and idempotent) seed of user-editable dotfiles from
  # ~/dotfiles/config/* to the live XDG locations. The model is:
  #   - repo is the source for the INITIAL content (this seed)
  #   - live (~/.config/..., ~/.zshrc) is the source thereafter
  #   - bin/sync-dotfiles (systemd path unit) auto-mirrors live -> repo
  # Seed is `--no-clobber`: existing live files (already edited) are
  # never overwritten. Safe to run on every activation. See SYNC.md.
  home.activation.seed-dotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    seed() {
      local src="$1" dst="$2"
      if [ ! -e "$dst" ] && [ -e "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp -r "$src" "$dst"
        echo "Seeded: $dst"
      fi
    }

    seed "$HOME/dotfiles/config/zsh/.zshrc" "$HOME/.zshrc"
    seed "$HOME/dotfiles/config/zed/settings.json" "$HOME/.config/zed/settings.json"
    seed "$HOME/dotfiles/config/ghostty/config" "$HOME/.config/ghostty/config"
    seed "$HOME/dotfiles/config/topgrade.toml" "$HOME/.config/topgrade.toml"
    seed "$HOME/dotfiles/config/opencode" "$HOME/.config/opencode"
    seed "$HOME/dotfiles/config/autostart/ferdium.desktop" "$HOME/.config/autostart/ferdium.desktop"
    seed "$HOME/dotfiles/config/cosmic/com.system76.CosmicComp/v1/keyboard_config" "$HOME/.config/cosmic/com.system76.CosmicComp/v1/keyboard_config"
    seed "$HOME/dotfiles/config/omo/omo.jsonc" "$HOME/.omo/omo.jsonc"
  '';
}
