{
  config,
  lib,
  pkgs,
  ...
}:

# Self-updating AppImage manager.
#
# Apps that ship their own auto-updater (electron-builder + AppImageUpdate)
# can't update when installed via nixpkgs, because the binary lives in
# /nix/store (read-only). This module moves those apps to ~/Applications/ and
# exposes them on PATH through wrapper scripts in ~/.local/bin/.
#
# After the first `nixup`, the apps can update themselves in-place. Day-to-day
# auto-updates work three ways:
#   1. In-app "Update" button (electron-builder's autoUpdater, default for both
#      Rambox and Ferdium).
#   2. `appimageupdatetool ~/Applications/<name>.AppImage` (CLI, zsync deltas).
#   3. `~/.local/bin/<name> --appimage-update` (electron-builder passthrough).
#
# Adding a new app: append an entry to `apps` below with `url` and (optionally)
# `execArgs` + `desktop`.
#
# Major-version bumps: when the upstream filename pattern changes (e.g.
# `Rambox-2.7.0-...AppImage` -> `Rambox-2.8.0-...AppImage`), update the `url`,
# delete the old `~/Applications/<name>.AppImage`, and re-run `nixup`.

let
  apps = {
    rambox = {
      url = "https://github.com/ramboxapp/download/releases/download/v2.7.0/Rambox-2.7.0-linux-x64.AppImage";
      # Electron apps need explicit Wayland flags to render crisply on
      # fractional-scaled Wayland sessions (the same problem the old
      # `ramboxWrapped` symlinkJoin solved; see home.nix history for refs).
      execArgs = "--enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer --ozone-platform=wayland";
      desktop = {
        name = "Rambox";
        comment = "Workspace messenger that combines many apps into one";
        categories = [
          "Network"
          "InstantMessaging"
        ];
      };
    };

    ferdium = {
      url = "https://github.com/ferdium/ferdium-app/releases/download/v7.1.2/Ferdium-linux-Portable-7.1.2-x86_64.AppImage";
      execArgs = "--enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer --ozone-platform=wayland";
      desktop = {
        name = "Ferdium";
        comment = "Multi-platform messaging app based on Franz";
        categories = [
          "Network"
          "InstantMessaging"
        ];
      };
    };
  };

  appsDir = "${config.home.homeDirectory}/Applications";
  binDir = "${config.home.homeDirectory}/.local/bin";

  # `name` below is the attrset key (also the on-PATH wrapper name, e.g.
  # "rambox"). `app.desktop.name` is the human-readable Name= in the
  # .desktop file. The wrapper has to be reachable by a stable identifier
  # so the systemd user service and `config-files.nix` autostart can keep
  # referring to a single name even as the AppImage inside is updated.
  installApp = name: app: ''
    # ${name}
    if [ ! -f ${appsDir}/${name}.AppImage ]; then
      mkdir -p ${appsDir}
      ${pkgs.curl}/bin/curl -fL --retry 3 --connect-timeout 30 \
        -o ${appsDir}/${name}.AppImage ${app.url}
      ${pkgs.coreutils}/bin/chmod +x ${appsDir}/${name}.AppImage
    fi
    ${pkgs.coreutils}/bin/mkdir -p ${binDir}
    ${pkgs.coreutils}/bin/install -m755 ${pkgs.writeShellScript "${name}-appimage-wrapper" ''
      exec ${appsDir}/${name}.AppImage ${app.execArgs or ""} "$@"
    ''} ${binDir}/${name}
  '';
in
{
  # Desktop entries so the apps show up in app launchers and the .desktop
  # autostart file in config-files.nix keeps working. `Icon` points at the
  # AppImage directly — the desktop environment extracts the embedded icon
  # from the squashfs. `settings` is the home-manager passthrough for
  # arbitrary [Desktop Entry] keys (e.g. StartupWMClass, which doesn't have
  # a first-class option).
  xdg.desktopEntries = lib.mapAttrs (name: app: {
    name = app.desktop.name;
    comment = app.desktop.comment or null;
    categories = app.desktop.categories or [ ];
    exec = "${name} %U";
    icon = "${appsDir}/${name}.AppImage";
    terminal = false;
    type = "Application";
    settings = {
      StartupWMClass = app.desktop.name;
    };
  }) apps;

  # Runs on every `home-manager switch` after the new generation is linked.
  # Idempotent: skips the download when the AppImage already exists, so the
  # app's own self-updates aren't clobbered on subsequent switches.
  home.activation.installAppImages = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    lib.concatStrings (lib.mapAttrsToList installApp apps)
  );
}
