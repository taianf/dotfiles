{ pkgs, ... }: {
  users.users."taian" = {
    isNormalUser = true;
    description = "Taian Fonseca Feitosa";
    extraGroups = [
      "i2c"
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
  };
}
