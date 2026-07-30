# dotfiles

NixOS + Home Manager configuration managed as a Git repo.

## Structure

```text
dotfiles/
├── flake.nix                      # Flake entry point (inputs, NixOS + Home Manager outputs)
├── home.nix                       # Home Manager entry point (imports home/ modules)
├── SYNC.md                        # Dotfile sync workflow (live wins, repo mirrors)
├── AGENTS.md                      # Agent instructions for AI coding tools
├── .pre-commit-config.yaml        # Pre-commit hooks (nixfmt, ruff, etc.)
├── .sync-ignore                   # rsync excludes for bin/sync-dotfiles
├── .gitignore
├── secrets.yaml                   # Encrypted secrets (sops-nix) — safe to commit
├── bin/                           # Custom scripts (added to PATH)
│   ├── nixup                      # Rebuild script
│   ├── nixflix                    # CLI wrapper for the media stack
│   ├── sync-dotfiles              # Auto-sync live -> repo (called by systemd path unit)
│   └── sync-dotfiles-on-boot      # Additive repo -> live on boot
├── config/                        # User-editable dotfiles (mirrored to ~/.config/ and ~/)
│   ├── zsh/.zshrc
│   ├── zed/settings.json
│   ├── ghostty/config
│   ├── topgrade.toml
│   ├── opencode/...
│   ├── autostart/ferdium.desktop
│   └── cosmic/.../keyboard_config
└── nixos/
    ├── configuration.nix          # Main NixOS config — symlinked to /etc/nixos/
    ├── default.nix                # Shared NixOS config (imported by all machines)
    ├── locale.nix                 # Timezone, locale, keymap
    ├── desktop.nix                # Display manager, desktop environments, pipewire, SSH
    ├── programs.nix               # NixOS-level program config (nix-ld, firefox, zsh)
    ├── hardware.nix               # System packages, podman, i2c
    ├── users.nix                  # User account
    ├── nvidia.nix                 # Nvidia GPU module (imported per-machine if needed)
    ├── sops.nix                   # Sops-nix secrets config
    └── nixflix/                   # Nixflix media stack config
        └── default.nix
```

## How it works

Two layers of Nix manage your system, plus a file-based dotfile sync
on top:

- **NixOS** (system) — `dotfiles/nixos/` (symlinked to `/etc/nixos/`):
  Boot, hardware, networking, services, secrets
- **Home Manager** (user) — `dotfiles/home.nix` + `dotfiles/home/`:
  Packages, programs, dotfiles seeding, systemd user services
- **Live dotfiles** — `dotfiles/config/*` are real files in `~/` and
  `~/.config/`, auto-synced to the repo. See [SYNC.md](./SYNC.md).

### Home Manager (`dotfiles/home/`)

Entry point is `home.nix`, which imports domain modules from `home/`:

- `packages.nix` — user packages that have no `programs.*` module
  (`ferdium`, `google-chrome`, `sops`, `prek`, `nixfmt`, `ggshield`,
  `nh`, `nil`, `nixd`, `python3`, `statix`, `wget`, `herdr`).
- `programs.nix` — `programs.*` configuration: zsh, git, ghostty,
  opencode, fzf, bun, **uv**, **npm** (replaces ad-hoc `nodejs` in
  `home.packages`), topgrade, gh, spotify-player, zed-editor (package
  only — settings are file-based), autojump, codegraph activation.
- `config-files.nix` — empty. Legacy XDG file entries have moved to
  the file-based sync model.
- `services.nix` — systemd user services: `dotfiles-sync` (path unit
  + oneshot that runs `bin/sync-dotfiles`), `dotfiles-sync-on-boot`
  (oneshot that runs `bin/sync-dotfiles-on-boot`), `ferdium` (autostart).

## Setup on a new machine

### 1. Install NixOS + clone dotfiles

```bash
# After installing NixOS, clone the dotfiles
git clone <repo-url> ~/dotfiles
```

### 2. Generate hardware configuration

```bash
sudo nixos-generate-config --show-hardware-config | sudo tee /etc/nixos/hardware-configuration.nix
```

### 3. Link the NixOS config

```bash
sudo ln -sf ~/dotfiles/nixos/configuration.nix /etc/nixos/configuration.nix
```

### 4. Edit machine-specific values

Open `dotfiles/nixos/configuration.nix` and change:

```nix
# Change per machine:
networking.hostName = "my-machine";   # ← your hostname
```

If the machine has an Nvidia GPU, uncomment `./nvidia.nix` in the imports. If not, comment it out or delete the line.

### 5. First rebuild

```bash
nixup             # System + Home Manager, errors-only by default
nixup --verbose   # Stream full output
nixup --dry-run   # Check + parse + build activation package, do not switch
```

### 6. Set up secrets (sops-nix)

Generate an age key from your host SSH key:

```bash
mkdir -p ~/.config/sops/age
sudo sh -c 'nix-shell -p ssh-to-age --run "ssh-to-age -private-key < /etc/ssh/ssh_host_ed25519_key" > /tmp/age-key'
sudo chown $USER:users /tmp/age-key
cp /tmp/age-key ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
rm /tmp/age-key
```

Create the `.sops.yaml` config:

```bash
# Get your age public key
sudo sh -c 'nix-shell -p ssh-to-age --run "ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key | ssh-to-age"'

# Create .sops.yaml with that key
cat > ~/dotfiles/.sops.yaml << EOF
keys:
  - &host <your-age-public-key>
creation_rules:
  - age: *host
EOF
```

Create the encrypted secrets file with initial values:

```bash
nix run nixpkgs#sops -- --encrypt --age <your-age-public-key> > ~/dotfiles/secrets.yaml << 'EOF'
sonarr:
  api_key: "changeme"
  password: "changeme"
radarr:
  api_key: "changeme"
  password: "changeme"
lidarr:
  api_key: "changeme"
  password: "changeme"
prowlarr:
  api_key: "changeme"
  password: "changeme"
sabnzbd:
  api_key: "changeme"
  nzb_key: "changeme"
  username: "admin"
  password: "changeme"
jellyfin:
  api_key: "changeme"
  admin_password: "changeme"
seerr:
  api_key: "changeme"
EOF
```

The encrypted `secrets.yaml` is safe to commit. To add another machine's SSH host key:

```bash
sops updatekeys secrets.yaml
```

### 7. Activate Home Manager (handled by `nixup` from step 5)

`nixup` runs `nixos-rebuild` and `home-manager` independently. The
seed-dotfiles activation copies `~/dotfiles/config/*` into
`~/.config/*` (and `~/.zshrc`) on the first run, so dotfiles are
ready immediately.

### 8. Enable pre-commit hooks (optional)

```bash
git config --local core.hooksPath .git/hooks
uvx prek install --overwrite
```

See [AGENTS.md](./AGENTS.md) for the per-machine prek install
workaround when a global `core.hooksPath` is set.

## Applying changes

```bash
# After editing NixOS config (dotfiles/nixos/) or Home Manager
# (home/ modules, home.nix):
nixup

# Dotfile edits in ~/.config/ or ~/.zshrc auto-commit within seconds
# via bin/sync-dotfiles (systemd path unit). Push when ready:
cd ~/dotfiles && git push
```

See [SYNC.md](./SYNC.md) for the full sync workflow.

## Key concepts

- **`nix-ld`** — enabled in shared config so uv and other tools that
  download dynamically linked binaries work on NixOS.
- **`programs.*` over `home.packages`** — when a Home Manager module
  exists (e.g. `programs.uv`, `programs.npm`), use it. `home.packages`
  is for packages with no module (Electron apps, single-binary CLIs,
  LSP servers). See `AGENTS.md`.
- **Live dotfiles, repo mirror** — every config the user wants to
  tweak lives as a real file in `~/.config/` (or `~/.zshrc`). The
  repo is an auto-synced mirror. See [SYNC.md](./SYNC.md).
- **`dotfiles-sync.path`** — a systemd user path unit watches
  `~/.config` for changes. On any change, `bin/sync-dotfiles` runs and
  mirrors live → repo with `rsync` (excludes from `.sync-ignore`),
  then `git add -A && git commit && git push`.
- **`dotfiles-sync-on-boot.service`** — pulls main on boot, then
  ADDITIVE-deploys new files (where live is missing) to `~/.config/`.
  Never overwrites an existing live file.
- **`bin/nixup`** — the canonical rebuild script. Runs the system
  and home rebuilds independently and prints a per-step summary.
- **`*.bak` files** — gitignored; used for local backups before
  config changes.
- **sops-nix** — uses each machine's SSH host key
  (`/etc/ssh/ssh_host_ed25519_key`) to decrypt `secrets.yaml`. No extra
  key management needed.

## Useful commands

```bash
# Check Home Manager news (changelog)
home-manager news

# Update flake inputs (latest nixpkgs + home-manager)
nix flake update

# Edit encrypted secrets
nixflix secrets edit      # opens sops editor
nixflix secrets show      # decrypt and print all secrets

# Nixflix media stack (Sonarr, Radarr, Jellyfin, etc.)
nixflix restart           # restart all services
nixflix refresh           # re-run config oneshot services
nixflix clean             # wipe state data + recreate dirs
nixflix full-refresh      # clean + rebuild + re-apply config
nixflix setup             # recreate jellyfin directories
nixflix check             # health check (services + API + integrations)
nixflix secrets {edit|show}

# Add another machine's key to secrets
sops updatekeys secrets.yaml
```
