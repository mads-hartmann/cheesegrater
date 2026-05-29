{
  config,
  lib,
  pkgs,
  self,
  ...
}:

let
  cfg = config.services.affineur;
  ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_2;
  affineur = ocamlPackages.callPackage ../../tools/affineur/package.nix {
    inherit self ocamlPackages;
  };
in
{
  options.services.affineur = {
    enable = lib.mkEnableOption "affineur HTTP server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on.";
    };

    repoPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nixos";
      description = "Path to the cheesegrater git repository.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.affineur = {
      description = "affineur HTTP server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        PORT = toString cfg.port;
        REPO_PATH = toString cfg.repoPath;
        JS_PATH = "${affineur}/share/affineur/main.js";
      };

      serviceConfig = {
        ExecStart = "${affineur}/bin/affineur";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        # Allow reading the git repo
        ReadOnlyPaths = [ (toString cfg.repoPath) ];
      };

      path = [ pkgs.git ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
