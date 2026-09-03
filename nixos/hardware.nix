{ pkgs, waydroid-script, ... }: {
  hardware.i2c.enable = true;

  environment.systemPackages = with pkgs; [
    ddcutil
    ddcui
    wl-clipboard
    xclip
    waydroid-helper
  ];

  nixpkgs.config.allowUnfree = true;

  environment.enableAllTerminfo = true;

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
    };
    waydroid = {
      enable = true;
      package = pkgs.waydroid-nftables;
    };
  };

  systemd.services.waydroid-fix-images-path = {
    description = "Fix waydroid images_path to use /var/lib/waydroid/images";
    wantedBy = [ "multi-user.target" ];
    before = [ "waydroid-container.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "waydroid-fix-images-path" ''
        if [ -f /var/lib/waydroid/waydroid.cfg ]; then
          sed -i 's|images_path = /etc/waydroid-extra/images|images_path = /var/lib/waydroid/images|' /var/lib/waydroid/waydroid.cfg
        fi
      '';
    };
  };

  systemd.services.waydroid-post-install = {
    description = "Post-install waydroid extras (gapps, libhoudini)";
    after = [ "waydroid-container.service" ];
    wants = [ "waydroid-container.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "waydroid-post-install" ''
        set -e
        FLAG=/var/lib/waydroid/.post-install-done
        if [ -f "$FLAG" ]; then
          exit 0
        fi
        sleep 10
        ${waydroid-script.packages.${pkgs.system}.default}/bin/waydroid-script install gapps || true
        ${waydroid-script.packages.${pkgs.system}.default}/bin/waydroid-script install libhoudini || true
        touch "$FLAG"
      '';
    };
  };

}
