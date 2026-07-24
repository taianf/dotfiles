# AGENTS.md — Rules for this dotfiles repo

## Architecture

This repo manages both **NixOS** (system) and **Home Manager** (user) configuration.

- `nixos/` — shared NixOS modules (imported by `/etc/nixos/configuration.nix`)
- `home.nix` / `flake.nix` — Home Manager (user-level packages, programs, shell, dotfiles)
- Machine-specific NixOS config stays in `/etc/nixos/` (not in this repo)

## Rules

### Package management

- **Prefer `programs.*` over `home.packages`** whenever a Home Manager module exists.
  Example: use `programs.git.enable = true` instead of adding `git` to `home.packages`.
  Search available modules at <https://home-manager-options.extranix.com/>
- **Don't add to `home.packages`** what `programs.*` already installs.
  Example: don't put `git` in packages if `programs.git.enable = true`.
- **Don't use `extraPackages`** for tools already in `home.packages` (they share the same PATH).

### NixOS config

- Keep `/etc/nixos/configuration.nix` **minimal** — only machine-specific things
  (bootloader, hostname, hardware imports).
- **Shared NixOS config** goes in `nixos/default.nix` and is imported by all machines.
- **User-level config** (packages, dotfiles, shell) belongs in Home Manager, not NixOS.
  Example: dotfiles sync service is a `systemd.user.services` in `home.nix`,
  not `systemd.services` in NixOS config.

### Zsh

- Use `programs.zsh.initContent`, not `initExtra` (deprecated).
- Default shell is set via `users.users.<name>.shell = pkgs.zsh` in NixOS
  and `programs.zsh.enable = true` in both NixOS and Home Manager.

### Branching

- **Never commit to `main`** — a pre-commit hook (`no-commit-to-branch`) blocks it.
- Always create a feature branch, push, and open a PR.
- Use `git checkout -b <branch-name>` to start a new branch.
- **Never merge PRs** — open the PR and let the user review and merge it.

### Worktrees

- **Always work in a git worktree** to avoid conflicting with parallel agents.
  Create one from `main` on each session:

  ```bash
  git worktree add -b <branch-name> /tmp/opencode/<branch-name> main
  ```

  Work inside `/tmp/opencode/<branch-name>` and commit/push from there.
  Clean up when done:

  ```bash
  git worktree remove /tmp/opencode/<branch-name> && git branch -D <branch-name>
  ```

### Git / dotfiles sync

- Use `git -C <path>` for regular repos. `--git-dir` / `--work-tree` is for bare repos.
- `home.stateVersion` and `system.stateVersion` are **never updated** after initial setup.

### Secrets

- Use `sops-nix` for managing secrets (API keys, passwords).
- Secrets go in a `secrets.yaml` encrypted with sops, referenced via `config.sops.secrets.<name>.path`.

### Safety

- **Back up before changing system configs**: `sudo cp /etc/nixos/configuration.nix /etc/nixos/configuration.nix.bak`
- `.bak` files are gitignored — keep them local.

### Pre-commit hooks

- Use `prek` (not `pre-commit` directly) to run pre-commit hooks:

  ```bash
  prek run --all-files   # run all hooks on all files
  prek run <hook-id>     # run a single hook
  ```

- Python linting is handled by ruff via pre-commit. Config is in `nixos/nixflix/pyproject.toml`.

- Ruff rules used: `I` (isort), `F` (pyflakes — unused imports, undefined names), `W`/`E` (pep8), `PL` (pylint), `RUF` (ruff-specific).

### Rebuild command

```bash
nixup             # quiet (errors only)
nixup --verbose   # full output
```

### Updating

```bash
nix flake update   # update flake.lock (latest nixpkgs + home-manager)
nixup              # apply updated packages
home-manager news  # check for breaking changes
```
