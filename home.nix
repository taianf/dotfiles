{
  config,
  pkgs,
  herdr,
  ...
}:
{
  imports = [
    ./home/packages.nix
    ./home/config-files.nix
    ./home/programs.nix
    ./home/services.nix
  ];

  home = {
    stateVersion = "23.11";
    homeDirectory = "/home/taian";
    username = "taian";
  };
}
