{ pkgs, ... }:

{
  languages.ocaml = {
    enable = true;
    packages = pkgs.ocaml-ng.ocamlPackages_5_2;
  };

  packages = with pkgs.ocaml-ng.ocamlPackages_5_2; [
    async
    core
    core_unix
    cohttp-async
    yojson
    dune_3
  ];
}
