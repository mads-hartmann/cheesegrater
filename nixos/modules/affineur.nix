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

    repoGroup = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = ''
        Group that owns the git repository. The service user joins this group
        so it can read the repository's commit history. With NixOS's default
        umask the repo's files and directories are group-readable, so the
        default ("users", the primary group of a normal user) works without
        changing any on-disk permissions.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # A dedicated system user rather than DynamicUser. A transient dynamic uid
    # belongs to no relevant group, so it cannot traverse into the repo
    # (chdir: Permission denied) and cannot establish a system D-Bus
    # connection to query systemd (systemctl: Transport endpoint is not
    # connected). A stable user that joins the repo's group fixes both:
    # group membership grants read access to the repo, and a real (non
    # transient) identity can talk to the system bus.
    users.users.affineur = {
      isSystemUser = true;
      group = "affineur";
      extraGroups = [ cfg.repoGroup ];
      description = "affineur HTTP server";
    };
    users.groups.affineur = { };

    systemd.services.affineur = {
      description = "affineur HTTP server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        PORT = toString cfg.port;
        REPO_PATH = toString cfg.repoPath;
        JS_PATH = "${affineur}/share/affineur/main.js";

        # The service user is not the repo owner, so git's "dubious ownership"
        # check would abort `git log`. Mark the repo as trusted via the
        # environment so we don't depend on any on-disk git config.
        GIT_CONFIG_COUNT = "1";
        GIT_CONFIG_KEY_0 = "safe.directory";
        GIT_CONFIG_VALUE_0 = toString cfg.repoPath;
      };

      serviceConfig = {
        ExecStart = "${affineur}/bin/affineur";
        Restart = "on-failure";
        RestartSec = "5s";

        User = "affineur";
        Group = "affineur";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        # The repo lives under /home, which ProtectHome makes inaccessible.
        # A read-only bind mount re-exposes just the repo into the sandbox so
        # `git log` can read history while the rest of /home stays hidden.
        # systemd creates the intermediate mount points as root, so the home
        # directory's own 0700 mode does not block traversal; only the repo's
        # (group-readable) permissions apply.
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
