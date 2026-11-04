{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.graveyard;

  # Vector reads the token from its systemd credential; the string option puts
  # it in the world-readable store.
  tokenFile =
    if cfg.betterStackTokenFile != null then cfg.betterStackTokenFile
    else pkgs.writeText "graveyard-better-stack-token" cfg.betterStackToken;
in
{
  options.services.graveyard = {
    betterStackToken = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Better Stack source token (stored world-readable; prefer betterStackTokenFile). Setting either enables log shipping.";
      example = "your-betterstack-source-token";
    };
    betterStackTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Root-only file holding the Better Stack source token";
      example = "/run/agenix/graveyard-better-stack-token";
    };
  };

  config = mkIf (cfg.enable && (cfg.betterStackToken != null || cfg.betterStackTokenFile != null)) {
    assertions = [{
      assertion = cfg.betterStackToken == null || cfg.betterStackTokenFile == null;
      message = "services.graveyard: set at most one of betterStackToken and betterStackTokenFile";
    }];

    services.vector = {
      enable = true;

      settings = {
        secret.graveyard = {
          type = "directory";
          path = "/run/credentials/vector.service";
          remove_trailing_whitespace = true;
        };

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
              token = "SECRET[graveyard.better_stack_token]";
            };
          };
        };
      };
    };

    systemd.services.vector = {
      after = [ "graveyard.service" "nginx.service" ];
      serviceConfig = {
        SupplementaryGroups = [ "web" ];
        LoadCredential = [ "better_stack_token:${tokenFile}" ];
      };
    };
  };
}
