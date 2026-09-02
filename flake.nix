{
  description = "Home Manager configuration of taian";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kilocode = {
      url = "github:Kilo-Org/kilocode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    vpn-confinement = {
      url = "github:Maroka-chan/VPN-Confinement";
      flake = false;
    };
    declarative-flatpak = {
      url = "github:in-a-dil-emma/declarative-flatpak/latest";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      herdr,
      kilocode,
      nix-cachyos-kernel,
      vpn-confinement,
      declarative-flatpak,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."taian" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [ ./home.nix ];

        extraSpecialArgs = {
          inherit herdr kilocode;
        };
      };

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit vpn-confinement declarative-flatpak;
        };
        modules = [
          declarative-flatpak.nixosModules.default
          ./nixos/configuration.nix
          { nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ]; }
        ];
      };
    };
}
