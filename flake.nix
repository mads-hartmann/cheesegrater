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

      pkgs = import nixpkgs {
        inherit system;
      };
      ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_2;
    in
    {
      packages.${system} = {
        affineur = ocamlPackages.callPackage ./tools/affineur/package.nix {
          inherit self ocamlPackages;
        };
        mdq = ocamlPackages.callPackage ./tools/mdq/package.nix {
          inherit self ocamlPackages;
        };
      };

      nixosConfigurations.cheesegrater = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          ./nixos/configuration.nix
          ./nixos/hardware-configuration.nix
          ./nixos/modules/affineur.nix
          ./nixos/modules/mdq.nix
          ./nixos/modules/reverse-proxy.nix
        ];
      };

      checks.${system}.pre-commit-check = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          nixfmt-rfc-style.enable = true;
          statix.enable = true;
        };
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          inherit (self.checks.${system}.pre-commit-check) shellHook;
          buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
        };

        affineur = pkgs.mkShell {
          dontDetectOcamlConflicts = true;
          buildInputs =
            import ./tools/affineur/deps.nix ocamlPackages
            ++ [ pkgs.watchexec ]
            ++ (with ocamlPackages; [
              ocaml
              dune_3
              findlib
            ]);
        };

        mdq = pkgs.mkShell {
          dontDetectOcamlConflicts = true;
          buildInputs =
            import ./tools/mdq/deps.nix ocamlPackages
            ++ [ pkgs.watchexec ]
            ++ (with ocamlPackages; [
              ocaml
              dune_3
              findlib
            ]);
        };
      };
    };
}
