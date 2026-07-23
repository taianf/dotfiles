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
    git
    google-chrome
    neovim
    nixfmt
    zed-editor
    uv
    zsh
    wget
    # ...
  ];

  home.file.".zshenv" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/.config/zsh/.zshenv";
  };

  xdg.configFile = {
    "zsh" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/.config/zsh";
      recursive = true;
    };
    # ...
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
