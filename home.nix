{
  callPackage,
  config,
  pkgs,
  ...
}:

{

  nixpkgs.config.allowUnfree = true;

  home.stateVersion = "23.11";
  home.homeDirectory = "/home/taian";
  home.username = "taian";

  home.packages = with pkgs; [
    google-chrome
    nixfmt
    uv
    wget
    zed-editor
  ];

  # OpenCode AI coding agent
  programs.opencode = {
    enable = true;
  };

  # Zsh with Oh My Zsh
  programs.zsh = {
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

  # Ensure the dotfiles repo is cloned at boot
  programs.git = {
    enable = true;
    settings.user.name = "Taian Fonseca Feitosa";
    settings.user.email = "taian.f.feitosa@gmail.com";
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
