# Polls the latest GitHub Release for this repo and runs nixos-rebuild switch
# when a new release tag is detected. The applied tag is persisted to
# /var/lib/nixos-auto-upgrade/current-tag so the service is idempotent across
# timer firings.
#
# The machine needs outbound HTTPS to github.com and raw.githubusercontent.com.
# No inbound access or deploy keys are required.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  repo = "mads-hartmann/cheesegrater";
  flakeAttr = "cheesegrater";
  stateDir = "/var/lib/nixos-auto-upgrade";
  stateFile = "${stateDir}/current-tag";

  upgradeScript = pkgs.writeShellScript "nixos-auto-upgrade" ''
    set -euo pipefail

    mkdir -p ${stateDir}

    # Fetch the latest release tag from the GitHub API.
    LATEST=$(${pkgs.curl}/bin/curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${repo}/releases/latest" \
      | ${pkgs.jq}/bin/jq -r '.tag_name')

    if [ -z "$LATEST" ] || [ "$LATEST" = "null" ]; then
      echo "No releases found, skipping."
      exit 0
    fi

    CURRENT=""
    if [ -f ${stateFile} ]; then
      CURRENT=$(cat ${stateFile})
    fi

    if [ "$LATEST" = "$CURRENT" ]; then
      echo "Already at $LATEST, nothing to do."
      exit 0
    fi

    echo "Upgrading $CURRENT -> $LATEST"
    ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
      --flake "github:${repo}/$LATEST#${flakeAttr}"

    echo "$LATEST" > ${stateFile}
    echo "Upgrade to $LATEST complete."
  '';
in
{
  systemd.services.nixos-auto-upgrade = {
    description = "NixOS auto-upgrade from GitHub releases";
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
