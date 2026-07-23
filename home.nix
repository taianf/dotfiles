{
  callPackage,
  config,
  pkgs,
  ...
}:

{
  # ...
  # Some default configuration
  # ...

  home.packages = with pkgs; [
    git
    google-chrome
    neovim
    nixfmt
    zed-editor
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
    userName = "Taian Fonseca Feitosa";
    userEmail = "taian.f.feitosa@gmail.com";
  };
  # Use a systemd service to pull the latest dotfiles on each boot
  systemd.services.dotfiles-sync = {
    description = "Sync dotfiles from Git";
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.git}/bin/git --git-dir=/home/taian/.dotfiles/ \
          --work-tree=/home/taian/ \
          pull origin main
      '';
      User = "taian";
    };
  };

}
