{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.graveyard;
  graveyardCfg = cfg;
in
{
  options.services.graveyard.betterStackToken = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Better Stack source token for log shipping. When set, enables Vector to forward nginx and PostgREST logs.";
    example = "your-betterstack-source-token";
  };

  config = mkIf (cfg.enable && cfg.betterStackToken != null) {
    services.vector = {
      enable = true;

      settings = {
        sources = {
          nginx_logs = {
            type = "file";
            include = [ cfg.accessLog ];
          };

          postgrest_logs = {
            type = "journald";
            include_units = [ "graveyard.service" ];
          };
        };

        transforms = {
          nginx_parsed = {
            type = "remap";
            inputs = [ "nginx_logs" ];
            source = ''
              .dt = del(.timestamp)
              .source = "nginx"
            '';
          };

          postgrest_parsed = {
            type = "remap";
            inputs = [ "postgrest_logs" ];
            source = ''
              .dt = del(.timestamp)
              .source = "postgrest"
            '';
          };
        };

        sinks = {
          better_stack = {
            type = "http";
            inputs = [ "nginx_parsed" "postgrest_parsed" ];
            uri = "https://in.logs.betterstack.com";
            encoding.codec = "json";
            auth = {
              strategy = "bearer";
              token = cfg.betterStackToken;
            };
          };
        };
      };
    };

    systemd.services.vector = {
      after = [ "graveyard.service" "nginx.service" ];
      serviceConfig.SupplementaryGroups = [ "web" ];
    };
  };
}
