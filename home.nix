{
  config,
  pkgs,
  lib,
  herdr,
  ...
}:
{
  imports = [
    ./home/packages.nix
    ./home/config-files.nix
    ./home/programs.nix
    ./home/apps.nix
    ./home/services.nix
  ];

  home = {
    stateVersion = "23.11";
    homeDirectory = "/home/taian";
    username = "taian";

    # CodeGraph: semantic code intelligence CLI / MCP server
    # (https://github.com/colbymchenry/codegraph). Installed as a bun
    # global after the first `home-manager switch` so the `codegraph`
    # binary is on PATH and the opencode MCP entry below resolves.
    activation.codegraph = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ! command -v codegraph >/dev/null 2>&1; then
        ${pkgs.bun}/bin/bun add -g @colbymchenry/codegraph
      fi
    '';
  };
}
