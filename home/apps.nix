{
  config,
  lib,
  pkgs,
  ...
}:

# AppImage manager for apps that need their own auto-updater.
#
# This is the **preferred** path for desktop apps — in particular Electron
# apps with electron-builder's autoUpdater (Rambox, etc.). The
# in-app updater needs to replace the running binary, which only works
# if the binary is in a writable path; nixpkgs puts it in /nix/store
# (read-only) and the updater fails (that's the original "my Rambox has
# an update but I can't update" complaint). Here we drop the
# AppImage into `~/Applications/` and let the app update itself in-place.
#
# Day-to-day auto-updates work three ways:
#   1. In-app "Update" button (electron-builder's autoUpdater, default for
#      Rambox).
#   2. `appimageupdatetool ~/Applications/<name>.AppImage` (CLI, zsync deltas).
#   3. `~/.local/bin/<name> --appimage-update` (electron-builder passthrough).
#
# **For apps that don't have an AppImage (CLI tools, libraries, headless
# services, non-updating GUI apps)**, prefer `home/packages.nix` — record
# them with `bin/nix-add nixpkgs#<pkg>`. The dotfiles ARE the manifest;
# `~/.nix-profile/manifest.json` is just a derived artifact. See
# `AGENTS.md` → "App distribution strategy" for the full decision tree.
#
# Adding a new AppImage app: append an entry to `apps` below with `url`
# and (optionally) `execArgs` + `desktop`. Major-version bumps (upstream
# filename pattern changes) require updating the `url`, deleting the old
# `~/Applications/<name>.AppImage`, and re-running `nixup`.
#
# Requires `programs.appimage.enable` and `programs.appimage.binfmt` in
# `nixos/programs.nix` — `binfmt_misc` is what lets the kernel `exec`
# an AppImage file directly (the AppImage's own shebang points at
# `/bin/bash`, which doesn't exist on NixOS).

let
  apps = {
    rambox = {
      url = "https://github.com/ramboxapp/download/releases/download/v2.7.0/Rambox-2.7.0-linux-x64.AppImage";
      # Electron Wayland flags — fix the fractional-scale blur. Same flag
      # set the old `waylandElectron` helper added to nixpkgs Electron
      # apps; here it's applied to the AppImage invocation.
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

    appmanager = {
      # GTK4/Vala, not Electron — handles Wayland natively, so no flags.
      # Not in nixpkgs; the AppImage is the only path.
      url = "https://github.com/kem-a/AppManager/releases/download/v3.7.3/AppManager-3.7.3-anylinux-x86_64.AppImage";
      execArgs = "";
      desktop = {
        name = "AppManager";
        comment = "MacOS-style AppImage installer and manager";
        categories = [
          "System"
          "PackageManager"
          "Utility"
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
  #
  # `prefixArgs` adds a leading space only when `execArgs` is non-empty, so
  # the rendered `exec` line stays clean for non-Electron apps that don't
  # need any flags (no trailing double-space).
  prefixArgs = args: if args == "" then "" else " ${args}";
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
      exec ${appsDir}/${name}.AppImage${prefixArgs (app.execArgs or "")} "$@"
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
