# nginx reverse proxy on port 80, routing by hostname to the local
# affineur and mdq services:
#
#   cheesegrater.local         -> affineur (config.services.affineur.port)
#   memory.cheesegrater.local  -> mdq      (config.services.mdq.port)
#
# The upstream ports are read from the affineur/mdq service options so the
# proxy stays in sync if either service's port changes. Hostname resolution
# is handled on the client side (e.g. an /etc/hosts entry pointing both names
# at this machine); nginx only matches on the Host header.
{
  config,
  lib,
  ...
}:

let
  cfg = config.services.reverse-proxy;
in
{
  options.services.reverse-proxy = {
    enable = lib.mkEnableOption "nginx reverse proxy for affineur and mdq";

    affineurHost = lib.mkOption {
      type = lib.types.str;
      default = "cheesegrater.local";
      description = "Host header that routes to the affineur service.";
    };

    mdqHost = lib.mkOption {
      type = lib.types.str;
      default = "memory.cheesegrater.local";
      description = "Host header that routes to the mdq service.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;

      recommendedProxySettings = true;
      recommendedOptimisation = true;

      virtualHosts = {
        ${cfg.affineurHost} = {
          locations."/".proxyPass = "http://127.0.0.1:${toString config.services.affineur.port}";
        };
        ${cfg.mdqHost} = {
          locations."/".proxyPass = "http://127.0.0.1:${toString config.services.mdq.port}";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
