{
  config,
  pkgs,
  lib,
  herdr,
  ...
}:

let
  # Electron apps default to XWayland on Linux, causing blurry renders on
  # fractional-scaled Wayland sessions (post-render upscale of a 1x window).
  # Force native Wayland rendering, native window decorations, and
  # PipeWire-based screen sharing — the canonical combination for Electron
  # on Wayland.
  #
  # See:
  #   - https://github.com/ferdium/ferdium-app/issues/1626 (blur on Wayland)
  #   - https://github.com/ferdium/ferdium-app/issues/32   (Wayland flags)
  #   - https://github.com/ferdium/ferdium-app/issues/1643 (screen sharing on NixOS)
  waylandFlags = "--enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer --ozone-platform=wayland";

  ferdiumWrapped = pkgs.symlinkJoin {
    name = "ferdium-wrapped";
    paths = [ pkgs.ferdium ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/ferdium \
        --add-flags "${waylandFlags}"
    '';
  };

  # Rambox is the same flavor of Electron app — same Wayland blur issue.
  ramboxWrapped = pkgs.symlinkJoin {
    name = "rambox-wrapped";
    paths = [ pkgs.rambox ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/rambox \
        --add-flags "${waylandFlags}"
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
  _module.args.ramboxWrapped = ramboxWrapped;

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
