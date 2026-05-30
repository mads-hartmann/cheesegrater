{ pkgs, ... }:

{
  languages.ocaml = {
    enable = true;
    packages = pkgs.ocaml-ng.ocamlPackages_5_2;
  };

  packages =
    import ./deps.nix pkgs.ocaml-ng.ocamlPackages_5_2
    ++ (with pkgs.ocaml-ng.ocamlPackages_5_2; [
      dune_3
    ]);
}
