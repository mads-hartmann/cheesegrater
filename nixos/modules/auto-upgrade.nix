# Periodically pulls the latest commit on main in the local checkout at
# ~/cheesegrater and runs nixos-rebuild switch against it. This keeps the
# machine tracking main without any inbound access or deploy keys — it only
# needs outbound HTTPS to github.com to fetch.
#
# The repository is private, so the pull authenticates with a fine-grained
# GitHub personal access token (Contents: read-only, scoped to this repo).
# The token is provisioned manually once, out of the Nix store, at
# tokenSource below. systemd's LoadCredential exposes it to this unit only,
# and a git credential helper feeds it to git over HTTPS. The token value
# never lands in the Nix store, the unit environment, or process argv.
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
  repoUrl = "https://github.com/mads-hartmann/cheesegrater.git";

  # Out-of-store file holding the fine-grained PAT, created manually as:
  #   sudo install -m 0600 -o root -g root /dev/stdin ${tokenSource} <<<'github_pat_...'
  # If it is missing the service fails to start with a clear error rather
  # than silently falling back to anonymous (and failing on a private repo).
  tokenSource = "/etc/nixos-auto-upgrade.token";

  # Per-run location the credential is staged to so the unprivileged repo
  # user can read it. Lives under the unit's RuntimeDirectory (tmpfs) and is
  # removed automatically when the oneshot unit deactivates.
  tokenStaged = "/run/nixos-auto-upgrade/gh-token";

  # Git credential helper. Git invokes it with "get"; it emits a fixed
  # username and the PAT read from the staged runtime file. The token is
  # never embedded in this script, so it stays out of the Nix store.
  credentialHelper = pkgs.writeShellScript "nixos-auto-upgrade-credential-helper" ''
    [ "$1" = "get" ] || exit 0
    echo "username=x-access-token"
    printf 'password=%s\n' "$(${pkgs.coreutils}/bin/cat ${tokenStaged})"
  '';

  upgradeScript = pkgs.writeShellScript "nixos-auto-upgrade" ''
    set -euo pipefail

    cd ${repoPath}

    # Stage the credential (exposed by systemd at $CREDENTIALS_DIRECTORY,
    # readable only by root) into a runtime file the repo user can read.
    ${pkgs.coreutils}/bin/install -m 0400 -o ${repoUser} \
      "$CREDENTIALS_DIRECTORY/gh-token" ${tokenStaged}

    # Force the remote to HTTPS before pulling. The service runs with a
    # minimal PATH that has no ssh binary, so an ssh:// remote would fail
    # with "cannot run ssh: No such file or directory". Pinning to HTTPS
    # keeps the design's "outbound HTTPS only, no deploy keys" property and
    # makes the service self-healing if the remote was ever set to SSH.
    ${pkgs.sudo}/bin/sudo -u ${repoUser} ${pkgs.git}/bin/git remote set-url origin ${repoUrl}

    # Pull as the repo owner so git object ownership stays correct, using the
    # credential helper to supply the PAT over HTTPS.
    ${pkgs.sudo}/bin/sudo -u ${repoUser} ${pkgs.git}/bin/git \
      -c credential.helper=${credentialHelper} \
      pull --ff-only

    # nixos-rebuild needs root to switch the system profile. Evaluating
    # ".#${flakeAttr}" makes Nix resolve "." to a git+file:// input, which is
    # fetched with libgit2 running as root against ${repoPath} (owned by
    # ${repoUser}). libgit2's dubious-ownership guard then aborts with
    # "repository path ... is not owned by current user (libgit2 error code =
    # 7)".
    #
    # Unlike the git CLI, libgit2 does NOT honour the GIT_CONFIG_COUNT /
    # GIT_CONFIG_KEY_* env mechanism, nor GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM,
    # for the safe.directory check — it only reads a real global gitconfig
    # located via $HOME. So mark the checkout safe by writing a throwaway
    # gitconfig into the unit's RuntimeDirectory (tmpfs, root-owned,
    # auto-removed on deactivation) and pointing HOME at it for this
    # invocation only. Nothing is written system-wide or persisted, and the
    # ${repoUser} pull above is unaffected (sudo reset its environment).
    export HOME=$RUNTIME_DIRECTORY
    ${pkgs.git}/bin/git config --file "$HOME/.gitconfig" \
      --add safe.directory ${repoPath}

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
      # Expose the PAT to this unit only, mounted root-readable at
      # $CREDENTIALS_DIRECTORY/gh-token.
      LoadCredential = [ "gh-token:${tokenSource}" ];
      # tmpfs scratch dir (/run/nixos-auto-upgrade) for the staged token,
      # auto-removed when the unit deactivates.
      RuntimeDirectory = "nixos-auto-upgrade";
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
