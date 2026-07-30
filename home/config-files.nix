# All XDG config entries that used to live here are now managed by the
# live-wins / repo-mirrors sync model (see bin/sync-dotfiles and the
# `seed-dotfiles` activation block in home/programs.nix). The seed
# activation copies ~/dotfiles/config/* -> ~/.config/* (and a few files
# to ~/) on first activation, with --no-clobber so existing user edits
# survive every rebuild. After that, the systemd `dotfiles-sync.path`
# unit in home/services.nix watches ~/.config and auto-commits live
# edits back to the repo.
_: { }
