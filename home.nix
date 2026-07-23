{
  callPackage,
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
        google-chrome
        nil
        nixd
        nixfmt
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

  programs = {
    ghostty.enable = true;
    opencode.enable = true;
    gh.enable = true;

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
      shellAliases = {
        rebuild = "sudo nixos-rebuild switch && nix run home-manager -- init --switch ~/dotfiles";
      };
      initContent = ''
        # Rebuild both NixOS and Home Manager
        rebuild() {
          sudo nixos-rebuild switch && nix run home-manager -- init --switch ~/dotfiles
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
