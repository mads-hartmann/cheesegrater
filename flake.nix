{
  description = "cheesegrater NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    git-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      git-hooks,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_2;
    in
    {
      packages.${system}.affineur = ocamlPackages.callPackage ./tools/affineur/package.nix {
        inherit self;
      };

      nixosConfigurations.cheesegrater = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          ./nixos/configuration.nix
          ./nixos/hardware-configuration.nix
          ./nixos/modules/affineur.nix
        ];
      };

      checks.${system}.pre-commit-check = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          nixfmt-rfc-style.enable = true;
          statix.enable = true;
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit-check) shellHook;
        buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
      };
    };
}
