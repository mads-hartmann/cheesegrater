{ ocamlPackages, self }:

ocamlPackages.buildDunePackage {
  pname = "affineur";
  version = "0.1.0";
  src = ./.;
  buildInputs = import ./deps.nix ocamlPackages;
  # Inject the git revision so /version returns the deployed commit SHA.
  VERSION = self.rev or "dev";
}
