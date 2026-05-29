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

      # Fix ppx_css build failure: sedlex 3.x rejects '\160'..'\255' as a
      # non-ASCII char-literal interval. Replace with Unicode codepoints.
      ocamlOverlay = final: prev: {
        ocaml-ng = prev.ocaml-ng // {
          ocamlPackages_5_2 = prev.ocaml-ng.ocamlPackages_5_2.overrideScope (
            ofinal: oprev: {
              ppx_css = oprev.ppx_css.overrideAttrs (old: {
                meta = old.meta // {
                  broken = false;
                };
                postPatch = (old.postPatch or "") + ''
                  sed -i "96s/.*/let non_ascii = [%sedlex.regexp? 0x80 .. 0xFF]/" \
                    vendor/css_parser/src/lexer.ml
                '';
              });
              bonsai = oprev.bonsai.overrideAttrs (old: {
                # The ppx_css override introduces a second cohttp via the
                # new scope; harmless but triggers the conflict detector.
                dontDetectOcamlConflicts = true;
              });
            }
          );
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ ocamlOverlay ];
      };
      ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_2;
    in
    {
      packages.${system}.affineur = ocamlPackages.callPackage ./tools/affineur/package.nix {
        inherit self ocamlPackages;
      };

      nixosConfigurations.cheesegrater = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          { nixpkgs.overlays = [ ocamlOverlay ]; }
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

      devShells.${system} = {
        default = pkgs.mkShell {
          inherit (self.checks.${system}.pre-commit-check) shellHook;
          buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
        };

        affineur = pkgs.mkShell {
          dontDetectOcamlConflicts = true;
          buildInputs =
            import ./tools/affineur/deps.nix ocamlPackages
            ++ (with ocamlPackages; [
              ocaml
              dune_3
              findlib
              js_of_ocaml-compiler
              ocaml-embed-file
            ]);
        };
      };
    };
}
