# ~/.zshrc — managed by ~/dotfiles, auto-synced from
# ~/.zshrc to ~/dotfiles/config/zsh/.zshrc by bin/sync-dotfiles.
#
# This file is a real file (not a symlink, not Nix-managed) so you can
# edit it freely. Changes auto-sync to the repo within seconds.
# See SYNC.md for the full sync workflow.

# Enable background subagents in opencode.
export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true

# Prepend ~/dotfiles/bin and ~/.bun/bin to PATH.
export PATH="$HOME/dotfiles/bin:$HOME/.bun/bin:$PATH"

# nixflix zsh completions (sourced best-effort).
source $HOME/dotfiles/zsh/completions/_nixflix 2>/dev/null

# prek (pre-commit) completions.
eval "$(COMPLETE=zsh prek)"

# `docker` shim: route to podman, with `docker compose` -> `podman compose`.
docker() {
  if [ "$1" = "compose" ]; then
    shift
    command podman compose "$@"
  else
    command podman "$@"
  fi
}
