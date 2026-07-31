{
  config,
  pkgs,
  lib,
  herdr,
  ...
}:

let
  # Ferdium is an Electron app that defaults to XWayland on Linux, which
  # causes a blurry/fuzzy look on fractional-scaled Wayland sessions
  # (post-render upscale of a 1x window). Force native Wayland rendering,
  # native window decorations, and PipeWire-based screen sharing — the
  # canonical combination for Ferdium on Wayland.
  #
  # See:
  #   - https://github.com/ferdium/ferdium-app/issues/1626 (blur on Wayland)
  #   - https://github.com/ferdium/ferdium-app/issues/32   (Wayland flags)
  #   - https://github.com/ferdium/ferdium-app/issues/1643 (screen sharing on NixOS)
  ferdiumWrapped = pkgs.symlinkJoin {
    name = "ferdium-wrapped";
    paths = [ pkgs.ferdium ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/ferdium \
        --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer" \
        --add-flags "--ozone-platform=wayland"
    '';
  };
in
{
  imports = [
    ./home/packages.nix
    ./home/config-files.nix
    ./home/programs.nix
    ./home/services.nix
  ];

  _module.args.ferdiumWrapped = ferdiumWrapped;

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
