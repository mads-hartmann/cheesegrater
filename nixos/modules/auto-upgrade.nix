# Periodically pulls the latest commit on main in the local checkout at
# ~/cheesegrater and runs nixos-rebuild switch against it. This keeps the
# machine tracking main without any inbound access or deploy keys — it only
# needs outbound HTTPS to github.com to fetch.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  flakeAttr = "cheesegrater";
  repoPath = "/home/mads/cheesegrater";
  repoUser = "mads";

  upgradeScript = pkgs.writeShellScript "nixos-auto-upgrade" ''
    set -euo pipefail

    cd ${repoPath}

    # Pull as the repo owner so git object ownership stays correct.
    ${pkgs.sudo}/bin/sudo -u ${repoUser} ${pkgs.git}/bin/git pull --ff-only

    # nixos-rebuild needs root to switch the system profile.
    ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake ".#${flakeAttr}"
  '';
in
{
  systemd.services.nixos-auto-upgrade = {
    description = "NixOS auto-upgrade from local checkout of main";
    # Requires network connectivity before running.
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = upgradeScript;
      # Run as root so nixos-rebuild can switch the system profile.
      User = "root";
    };
  };

  systemd.timers.nixos-auto-upgrade = {
    description = "Periodic NixOS auto-upgrade check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Check every 5 minutes.
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      # Spread load by up to 1 minute to avoid thundering-herd if you ever
      # run multiple machines.
      RandomizedDelaySec = "1min";
      Unit = "nixos-auto-upgrade.service";
    };
  };
}
