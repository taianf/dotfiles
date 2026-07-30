# AGENTS.md — Rules for this dotfiles repo

## Architecture

- `flake.nix` — entry point. Wires two outputs: `homeConfigurations."taian"` and
  `nixosConfigurations."nixos"`.
- `home.nix` — Home Manager entry. Imports `home/{packages,programs,config-files,services}.nix`.
  Also defines a custom `ferdiumWrapped` package (Wayland flags) and a codegraph
  bootstrap activation.
- `nixos/configuration.nix` — machine-specific. **Symlinked to
  `/etc/nixos/configuration.nix`** on the live host. Only safe machine-specific
  things live here (boot, hostname, hardware imports, stateVersion, and
  nixflix/cachyos/nvidia imports).
- `nixos/default.nix` — shared NixOS config imported by all machines. Imports
  `locale`, `desktop`, `programs`, `hardware`, `users`.
- `nixos/hardware-configuration.nix` — auto-generated per machine by
  `nixos-generate-config`. **Not in this repo.** The symlink in
  `nixos/configuration.nix` points to `/etc/nixos/hardware-configuration.nix`.
- `bin/nixup` — the canonical rebuild script (see Rebuild section).
- `bin/nixflix` — Python CLI wrapper (`uv run` in `nixos/nixflix/`) for the
  media stack.
- `secrets.yaml` — sops-nix encrypted secrets, safe to commit.
- `.opencode/`, `.omo/`, `node_modules/`, `result/`, `.venv/`, `.ruff_cache/`,
  `.mypy_cache/` — gitignored local state.

## Hard rules

### Package management

- **Prefer `programs.*` over `home.packages`** whenever a Home Manager module
  exists. Search at <https://home-manager-options.extranix.com/>.
- **Don't add to `home.packages`** what `programs.*` already installs — they
  share PATH.
- **Known exception**: `pkgs.nodejs` is in `home/packages.nix` because the
  pinned `home-manager` does not yet expose `programs.nodejs`. When bumped,
  switch to `programs.nodejs.enable = true` and remove from `home.packages`
  (see the comment block in `home/programs.nix`).
- `nixpkgs.config.allowUnfree = true` is required (ferdium, google-chrome).

### Zsh

- Use `programs.zsh.initContent`, not `initExtra` (deprecated).
- Default shell is set in **two places**: `users.users.taian.shell = pkgs.zsh`
  (NixOS) and `programs.zsh.enable = true` (both NixOS and Home Manager).

### NixOS vs Home Manager ownership

- `/etc/nixos/configuration.nix` stays minimal — only machine-specific things.
- Shared NixOS config goes in `nixos/default.nix` and is imported by all
  machines.
- User-level config (packages, dotfiles, shell, user systemd services) belongs
  in Home Manager. Example: `dotfiles-sync.service` is a
  `systemd.user.services.*` in `home/services.nix`, not a system service.

### Branching

- **Never commit to `main`** — the `no-commit-to-branch` pre-commit hook
  blocks it, **and** `dotfiles-sync.service` runs
  `git -C ~/dotfiles pull origin main` on every boot, so a main commit would
  propagate to the live host immediately.
- Always create a feature branch, push, and open a PR.
- **Never merge PRs** — open the PR and let the user review and merge.
- **Don't amend or force-push.** PRs are squash-merged, so each fix or
  follow-up should be its own commit. Linear per-commit history makes PR
  reviews easier to follow.
- A PR comment starting with `/oc` or `/opencode` triggers
  `.github/workflows/opencode.yml` (model: `opencode-go/deepseek-v4-flash`).

### Worktrees

Always work in a git worktree to avoid conflicting with parallel agents:

```bash
git worktree add -b <branch-name> /tmp/opencode/<branch-name> main
```

Work inside `/tmp/opencode/<branch-name>`. Clean up when done:

```bash
git worktree remove /tmp/opencode/<branch-name> && git branch -D <branch-name>
```

### State versions

`home.stateVersion` (in `home.nix`) and `system.stateVersion` (in
`nixos/configuration.nix`) are **never updated** after initial setup. Bumping
them triggers unwanted migrations.

### Git

- Use `git -C <path>` for regular repos. `--git-dir` / `--work-tree` is for bare
  repos only.

### Secrets

- Use `sops-nix` (`nixos/sops.nix`); secrets live in `secrets.yaml` at the repo
  root, encrypted with each host's `/etc/ssh/ssh_host_ed25519_key`. Add a new
  machine with `sops updatekeys secrets.yaml`.

### Safety

- Back up before changing system configs:
  `sudo cp /etc/nixos/configuration.nix /etc/nixos/configuration.nix.bak`.
  `.bak` files are gitignored — keep them local.

## Pre-commit hooks

Use `prek` (not `pre-commit` directly):

```bash
prek run --all-files   # all hooks, all files
prek run <hook-id>     # single hook
```

Relevant local hooks: `no-commit-to-branch`, `statix-check`/`statix-fix`,
`nixfmt-nix`, `ruff-check`/`ruff-format`, `mypy`, `markdownlint`, `yamllint`,
`gitleaks`, `ggshield`. Python lint rules (`I`, `F`, `W`/`E`, `PL`, `RUF`) live
in `nixos/nixflix/pyproject.toml`. CI skips `nixfmt-nix`, `statix-*`, and
`ggshield` (see `.pre-commit-config.yaml` `ci.skip`).

### First-time per-machine setup

`uvx prek install --overwrite` will fail with
`Refusing to install hooks because core.hooksPath is configured outside this repository`
when a global `core.hooksPath` is set (commonly ggshield's wrapper at
`~/.local/share/ggshield/git-hooks`). The wrapper already chains to a
repo-local `.git/hooks/pre-commit` if it exists, so just point this repo's
local path there and reinstall:

```bash
git config --local core.hooksPath .git/hooks
uvx prek install --overwrite
```

This applies to all worktrees too (worktrees share `.git/hooks/` via the common
git dir). The full commit chain becomes: ggshield wrapper → local pre-commit
(prek) → all configured hooks → `ggshield secret scan pre-commit`.

## Rebuilding

`bin/nixup` is the only supported entry point. It runs the system and home
rebuilds **independently** — one failure does not block the other — and prints
a per-step summary.

```bash
nixup             # quiet (errors only)
nixup --verbose   # stream full output
nixup --dry-run   # check + parse + build activation package, do not switch
```

Under the hood `nixup` runs
`sudo nixos-rebuild switch --impure --flake ~/dotfiles#nixos` then
`nix run home-manager -- init --switch ~/dotfiles -b backup`.

### Verifying Home Manager changes (do this before opening a PR)

`nix flake check --no-build` only validates the option-tree shape — it does
**not** catch missing/misspelled options in modules that are enabled but not
instantiated as top-level outputs (e.g. `programs.zsh.plugins`, custom plugin
attrsets, activation scripts). It happily returns `all checks passed!` while a
live `nixup` fails on `The option 'programs.<x>' does not exist`.

Before shipping a Home Manager change, run `nixup --dry-run`. It runs
`nix flake check`, parses every `*.nix` file, and builds
`homeConfigurations.taian.activationPackage` end-to-end — so option resolution
and `pkgs` references are fully evaluated without actually switching
generations. Only then is the change safe to ship via `nixup`.

If `nixup --dry-run` passes but a live `nixup` still fails, the issue is at
activation time (e.g. a `home.activation.*` script), not configuration
evaluation.

CI (`.github/workflows/ci.yml`) only runs `statix check` — it does **not** run
`nixup --dry-run` or `nix flake check`. Local verification is mandatory.

## Updating

```bash
nix flake update   # update flake.lock (latest nixpkgs + home-manager)
nixup              # apply
home-manager news  # check for breaking changes
```

## Non-obvious code facts

- `home.nix` defines `ferdiumWrapped` (a `symlinkJoin` over `pkgs.ferdium` with
  `makeWrapper` flags
  `--enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer
--ozone-platform=wayland`). Required to fix Ferdium's blurry render on
  fractional-scaled Wayland.
- `home/programs.nix` activation script bootstraps `codegraph` via
  `bun add -g @colbymchenry/codegraph` if it isn't on PATH. Don't move this —
  codegraph is on the critical path for the opencode MCP server.
- `home/programs.nix` activation script `seed-dotfiles` copies
  `~/dotfiles/config/*` → `~/.config/*` (and `~/.zshrc`) on first
  activation with `--no-clobber`. Idempotent. The list of mappings
  must stay in sync between `home/programs.nix` (seed), `bin/sync-dotfiles`
  (auto-mirror), and `bin/sync-dotfiles-on-boot` (additive deploy on
  boot). Update all three when adding a new tracked file.
- `home/services.nix` defines three `systemd.user.services` and one
  `systemd.user.paths`:
  - `dotfiles-sync.path` watches `~/.config` (PathChanged) and
    triggers `dotfiles-sync.service`.
  - `dotfiles-sync.service` (oneshot) runs `bin/sync-dotfiles` —
    mirrors live → repo and commits.
  - `dotfiles-sync-on-boot.service` (oneshot, default.target) runs
    `bin/sync-dotfiles-on-boot` — pulls main and additive-deploys new
    files. Never overwrites an existing live file.
  - `ferdium.service` (simple, autostart on `graphical-session.target`).
- `home/config-files.nix` is intentionally empty. All XDG file entries
  moved to the file-based sync model: content lives in `config/*`,
  seeded to live on first activation, mirrored back automatically.
- `home/programs.nix` programs list (search <https://home-manager-options.extranix.com/>
  before adding a new `home.packages` entry — most LSP servers and formatters
  have NO `programs.*` module, so they correctly stay in `home.packages`):
  zsh, git, ghostty, opencode, fzf, bun, **uv**, **npm** (replaces
  ad-hoc `pkgs.nodejs` in `home.packages` — see `programs.npm` default
  package is `pkgs.nodejs`), topgrade, gh, spotify-player, zed-editor
  (package only — settings are file-based, NOT `userSettings`),
  autojump. `programs.zsh.initContent` is empty on purpose: `~/.zshrc`
  is a real file in `config/zsh/.zshrc`, edited freely, auto-mirrored.
- `bin/nixflix` is a thin wrapper:
  `uv run --directory "$(dirname "$0")/../nixos/nixflix" python -m nixflix.cli "$@"`.
  Subcommands (see `zsh/completions/_nixflix`): `restart`, `refresh`,
  `clean`, `full-refresh`, `setup`, `secrets`, `check`. Always
  `nixflix secrets`, never `bin/secrets`; always `nixflix restart`,
  never `nixflix-restart`.
- `bin/sync-dotfiles` reads `~/dotfiles/.sync-ignore` for rsync
  excludes (defaults if missing). Idempotent: bails with
  `sync-dotfiles: no changes` if `git diff --cached --quiet`.
  Best-effort `git push` — a network failure logs a warning and
  leaves the commit local for the next run to push.

## Before opening a PR

Run all of these locally before pushing the branch and opening a PR.
CI only runs `statix check` and will not catch option-name typos,
broken activation scripts, or unrenderable Markdown.

```bash
# 1. The repo's primary verification. This is the one that catches
#    missing/misspelled options in modules that are enabled but not
#    instantiated as top-level outputs (e.g. custom `plugins` attrsets,
#    activation scripts). `nix flake check` alone will not catch these.
nixup --dry-run

# 2. Run every pre-commit hook on every file. Local prek only runs
#    hooks on staged files by default, which is the wrong thing when
#    you have unstaged WIP from auto-sync.
prek run --all-files

# 3. Confirm the diff matches the PR's stated intent.
git log --oneline main..HEAD   # atomic commits, each a logical chunk
git diff main...HEAD --stat    # scope is what you described

# 4. If you touched docs (README.md, SYNC.md, AGENTS.md), preview the
#    rendered Markdown and check for broken links, stale references,
#    and consistent terminology ("live wins, repo mirrors" not
#    "model A" or "symlink" — see SYNC.md for the canonical phrasing).

# 5. If you changed any tracked-config mapping (added a new file to
#    `config/`), verify the three places that need updating are all
#    consistent:
#    - home/programs.nix  -> home.activation.seed-dotfiles
#    - bin/sync-dotfiles   -> rsync (covers config/* -> ~/dotfiles/config/*)
#    - bin/sync-dotfiles-on-boot -> deploy() lines
#    A mismatch causes a new file to be missing on first install, or
#    to never auto-mirror, depending on which side is stale.

# 6. Push and open the PR. NEVER merge yourself — PRs are squash-merged
#    by the user. The PR body should summarize the WHY of the change
#    (not the WHAT — the diff shows the WHAT). Link SYNC.md if the
#    PR touches the dotfile sync model.
git push -u origin <branch>
gh pr create --fill --base main
```
