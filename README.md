# dotfiles

NixOS + Home Manager configuration managed as a Git repo.

## Structure

```text
dotfiles/
├── flake.nix                      # Flake entry point (inputs, NixOS + Home Manager outputs)
├── home.nix                       # Home Manager entry point (imports home/ modules)
├── .pre-commit-config.yaml        # Pre-commit hooks (nixfmt, ruff, etc.)
├── .gitignore
├── secrets.yaml                   # Encrypted secrets (sops-nix) — safe to commit
├── AGENTS.md                      # Agent instructions for AI coding tools
├── bin/                           # Custom scripts (added to PATH)
│   └── secrets                    # Manage encrypted secrets
├── home/                          # Home Manager domain modules
│   ├── packages.nix               # User packages (google-chrome, sops, etc.)
│   ├── config-files.nix           # XDG config file symlinks (zed, topgrade, opencode)
│   ├── programs.nix               # Program configuration (zsh, git, ghostty, etc.)
│   └── services.nix               # Systemd user services (dotfiles-sync, rambox)
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
    └── nixflix/
        └── default.nix            # Nixflix media stack config
```

## How it works

Two layers of Nix manage your system:

- **NixOS** (system) — `dotfiles/nixos/` (symlinked to `/etc/nixos/`):
  Boot, hardware, networking, services, secrets
- **Home Manager** (user) — `dotfiles/home.nix` + `dotfiles/home/`:
  Packages, dotfiles sync, shell, git, symlinks

### NixOS (`dotfiles/nixos/`)

- `configuration.nix` — main config, symlinked to `/etc/nixos/configuration.nix`.
  Imports `default.nix` and machine-specific modules.
- `default.nix` — shared config for all machines; imports domain modules:
  - `locale.nix` — timezone, locale, keymap
  - `desktop.nix` — display manager, desktop environments, audio, SSH
  - `programs.nix` — nix-ld, firefox, zsh
  - `hardware.nix` — system packages, podman, i2c
  - `users.nix` — user account
- `hardware-configuration.nix` — auto-generated per machine, stays in `/etc/nixos/`. Not in repo.
- `nvidia.nix` — Nvidia GPU config (imported per-machine if needed).
- `sops.nix` — sops-nix secrets config.
- `nixflix/` — Nixflix media stack (Sonarr, Radarr, Jellyfin, etc.).

### Home Manager (`dotfiles/home/`)

Entry point is `home.nix`, which imports domain modules from `home/`:

- `packages.nix` — user packages (google-chrome, sops, etc.)
- `config-files.nix` — XDG config symlinks (zed, topgrade, opencode)
- `programs.nix` — program config (zsh, git, ghostty, etc.)
- `services.nix` — systemd user services (dotfiles-sync, rambox)

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
# This will fail the first time because hardware-configuration.nix is missing.
# After step 2, it should work.
sudo nixos-rebuild switch
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

### 7. Activate Home Manager

```bash
nix run home-manager -- init --switch ~/dotfiles -b backup
```

### 8. Enable pre-commit hooks (optional)

```bash
pre-commit install
```

## Applying changes

After editing NixOS config (`dotfiles/nixos/`):

```bash
sudo nixos-rebuild switch --impure --flake ~/dotfiles#nixos
```

After editing Home Manager config (`home/` modules or `home.nix`):

```bash
home-manager init --switch ~/dotfiles
```

Or use the shorthand:

```bash
nixup
```

## Key concepts

- **`nix-ld`** — enabled in shared config so uv, and other tools that download
  dynamically linked binaries, work on NixOS.
- **`dotfiles-sync.service`** — a user-level systemd service defined in
  `home/services.nix` that runs `git pull` on boot to keep dotfiles up to date.
- **Dotfile symlinks** — `home/config-files.nix` uses `mkOutOfStoreSymlink` to symlink
  `.config/zsh` and `.zshenv` from this repo into your home, so edits in the
  repo take effect immediately.
- **`*.bak` files** — gitignored; used for local backups before config changes.
- **sops-nix** — uses each machine's SSH host key
  (`/etc/ssh/ssh_host_ed25519_key`) to decrypt `secrets.yaml`. No extra key
  management needed.

## Useful commands

```bash
# Check Home Manager news (changelog)
home-manager news

# Update flake inputs (latest nixpkgs + home-manager)
nix flake update

# Edit encrypted secrets
secrets edit         # opens sops editor
secrets show         # decrypt and print all secrets

# Restart all nixflix services (after changing passwords)
nixflix-restart

# Add another machine's key to secrets
sops updatekeys secrets.yaml
```
