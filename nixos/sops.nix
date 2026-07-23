# Sops-nix configuration for managing secrets
{ config, ... }:

{
  sops = {
    defaultSopsFile = ../secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
