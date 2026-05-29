{
  ocamlPackages,
  self,
  lib,
}:

let
  # The Jane Street libraries (async_js, bonsai) pin their own js_of_ocaml
  # (5.9.1), and the Dom_html in that library compiles to a call to the
  # caml_js_on_ie runtime primitive. The ocamlPackages scope's default
  # js_of_ocaml-compiler is a newer 6.x release whose runtime dropped that
  # primitive. Using the scope's compiler therefore produced a bundle that
  # links the 5.9.1 library code (which calls caml_js_on_ie) against a 6.x
  # runtime (which never defines it), causing the browser error:
  #   "Uncaught TypeError: runtime.caml_js_on_ie is not a function".
  #
  # The Ona dev shell happened to work because the Jane Street closure put
  # the matching 5.9.1 compiler first on PATH. To make the Nix package build
  # deterministic, resolve the compiler from the exact js_of_ocaml library
  # that async_js links, guaranteeing library and runtime stay on one version.
  inputsOf = p: (p.propagatedBuildInputs or [ ]) ++ (p.buildInputs or [ ]);
  jsooLib = lib.findFirst (
    p: (p.pname or "") == "js_of_ocaml"
  ) (throw "could not find js_of_ocaml in async_js inputs") (inputsOf ocamlPackages.async_js);
  jsooCompiler = lib.findFirst (
    p: (p.pname or "") == "js_of_ocaml-compiler"
  ) (throw "could not find js_of_ocaml-compiler in js_of_ocaml inputs") (inputsOf jsooLib);
in
ocamlPackages.buildDunePackage {
  pname = "affineur";
  version = "0.1.0";
  src = ./.;
  buildInputs = import ./deps.nix ocamlPackages;
  nativeBuildInputs = [
    jsooCompiler
    ocamlPackages.ocaml-embed-file
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
