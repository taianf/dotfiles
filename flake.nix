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
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    sops-nix.url = "github:Mic92/sops-nix";
    nixflix = {
      url = "github:kiriwalawren/nixflix";
      flake = false;
    };
    vpn-confinement = {
      url = "github:Maroka-chan/VPN-Confinement";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      herdr,
      nix-cachyos-kernel,
      sops-nix,
      nixflix,
      vpn-confinement,
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
          inherit herdr;
        };
      };

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit nixflix vpn-confinement;
        };
        modules = [
          sops-nix.nixosModules.sops
          ./nixos/configuration.nix
          { nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ]; }
        ];
      };
    };
}
