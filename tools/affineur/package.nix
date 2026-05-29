{
  ocamlPackages,
  self,
  lib,
}:

ocamlPackages.buildDunePackage {
  pname = "affineur";
  version = "0.1.0";
  src = ./.;
  buildInputs = import ./deps.nix ocamlPackages;
  nativeBuildInputs = with ocamlPackages; [
    js_of_ocaml-compiler
    ocaml-embed-file
  ];
  dontDetectOcamlConflicts = true;
  # Inject the git revision so /version returns the deployed commit SHA.
  VERSION = self.rev or "dev";

  # Override the build phase to build both the server and the JS frontend.
  # Use @all instead of -p to build everything including JS targets.
  buildPhase = ''
    runHook preBuild
    dune build @all
    runHook postBuild
  '';

  postInstall = ''
    mkdir -p $out/share/affineur
    cp _build/default/web/main.bc.js $out/share/affineur/main.js
  '';
}
