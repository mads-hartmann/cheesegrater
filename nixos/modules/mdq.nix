{
  config,
  lib,
  pkgs,
  self,
  ...
}:

let
  cfg = config.services.mdq;
  ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_2;
  mdq = ocamlPackages.callPackage ../../tools/mdq/package.nix {
    inherit self ocamlPackages;
  };
in
{
  options.services.mdq = {
    enable = lib.mkEnableOption "mdq markdown browser";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "Port to listen on.";
    };

    folders = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = [
        "/home/mads/cheesegrater/docs"
      ];
      description = ''
        Folders of markdown files to serve. A single folder is mounted at the
        site root; several folders are each mounted under their basename.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.mdq = {
      description = "mdq markdown browser";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        PORT = toString cfg.port;
        # Folders are passed colon-separated; the binary also accepts them as
        # positional arguments.
        DOCS_PATHS = lib.concatStringsSep ":" (map toString cfg.folders);
      };

      serviceConfig = {
        ExecStart = "${mdq}/bin/mdq";
        Restart = "on-failure";
        RestartSec = "5s";

        DynamicUser = true;

        # Hardening. mdq only reads the configured folders, so the sandbox can
        # be tight: no privilege escalation, a read-only view of the system,
        # and a private tmp. The served folders are re-exposed read-only below.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        PrivateTmp = true;

        # The docs live under /home, which we want hidden except for the served
        # folders. ProtectHome must be "tmpfs" rather than true here: with
        # "true", systemd mounts an empty, mode-000 directory over /home that
        # even the bind mounts below cannot be traversed through, so resolving
        # a served folder fails (realpath: Permission denied). "tmpfs" instead
        # mounts a fresh root-owned 0755 tmpfs over /home and creates the bind
        # mountpoints inside it as root (0755), so the service user can
        # traverse /home and /home/<user> regardless of their real 0700 mode;
        # only the folders' own permissions then apply.
        ProtectHome = "tmpfs";

        # Read-only bind mounts re-exposing just the served folders into the
        # sandbox so the server can read them while the rest of /home stays
        # hidden.
        BindReadOnlyPaths = map toString cfg.folders;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
