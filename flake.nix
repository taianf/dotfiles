{
  description = "Home Manager configuration of taian";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
  };

  outputs = {
    nixpkgs,
    home-manager,
    herdr,
    nix-cachyos-kernel,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    homeConfigurations."taian" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [./home.nix];

      extraSpecialArgs = {
        inherit herdr;
      };
    };

    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./nixos/configuration.nix
        {nixpkgs.overlays = [nix-cachyos-kernel.overlays.pinned];}
      ];
    };
  };
}
