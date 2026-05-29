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

        # The service runs as a DynamicUser, so the repo (owned by the human
        # user that cloned it) trips git's "dubious ownership" check and
        # `git log` aborts. Mark the repo as trusted via the environment so we
        # don't depend on any on-disk git config.
        GIT_CONFIG_COUNT = "1";
        GIT_CONFIG_KEY_0 = "safe.directory";
        GIT_CONFIG_VALUE_0 = toString cfg.repoPath;
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

        # The repo lives under /home, which ProtectHome makes inaccessible.
        # A read-only bind mount re-exposes just the repo into the sandbox so
        # `git log` can read history while the rest of /home stays hidden.
        # (ReadOnlyPaths alone does not bypass ProtectHome.)
        BindReadOnlyPaths = [ (toString cfg.repoPath) ];
      };

      # git: read commit history. systemd: query unit status via systemctl.
      path = [
        pkgs.git
        pkgs.systemd
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
