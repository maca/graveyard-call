{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.graveyard;
  dataDir = "/var/lib/graveyard";
  postgrestSocket = "/run/graveyard/graveyard.sock";
  serviceName = "graveyard";
  staticAssets = import ./static-assets.nix { inherit pkgs; };

  goose = pkgs.goose;
  migrationsDir = ../database/migrations;

  # Fetch pre-built Elm application from GitHub releases
  elmApp = pkgs.stdenv.mkDerivation {
    pname = "graveyard-elm";
    version = "latest";

    src = builtins.fetchurl "https://github.com/maca/graveyard-call/releases/latest/download/main.js";

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/main.js
    '';
  };

  # Fetch pre-built back-office Elm application from GitHub releases
  backOfficeElmApp = pkgs.stdenv.mkDerivation {
    pname = "graveyard-backoffice-elm";
    version = "latest";

    src = builtins.fetchurl "https://github.com/maca/graveyard-call/releases/latest/download/back-office.js";

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/back-office.js
    '';
  };

  # Create back-office index.html by copying local and replacing script src for production
  backOfficeIndex = pkgs.runCommand "back-office-index" { } ''
    ${pkgs.gnused}/bin/sed \
      -e 's|src="/back-office/main.js"|src="/back-office/back-office.js"|' \
      -e 's|http://localhost:4000/api|https://${cfg.domain}/api|g' \
      ${../back-office/static/index.html} > $out
  '';

  # Package main application static files
  mainStaticBundle = pkgs.runCommand "graveyard-main-static" { } ''
    mkdir -p $out
    cp -r ${../static}/* $out/
    cp ${elmApp}/main.js $out/main.js
  '';

  # Package back-office static files
  backOfficeBundle = pkgs.runCommand "graveyard-backoffice-static" { } ''
    mkdir -p $out
    cp ${backOfficeIndex} $out/index.html
    cp ${backOfficeElmApp}/back-office.js $out/back-office.js
    cp ${staticAssets.icono}/icono.min.css $out/icono.min.css
    cp ${staticAssets.milligram}/milligram.min.css $out/milligram.min.css
    cp ${../back-office/static/postgrest-admin.css} $out/postgrest-admin.css
  '';

  # PostgREST config file
  postgrestConf = pkgs.writeText "postgrest.conf" ''
    db-uri = "postgres:///?host=${cfg.databaseSocket}&dbname=${serviceName}"
    db-schemas = "graveyard"
    db-anon-role = "anonymous"
    jwt-secret = "${cfg.jwtSecret}"
    server-unix-socket = "${postgrestSocket}"
    log-level = "info"
  '';
in
{
  options.services.graveyard = {
    enable = mkEnableOption "Graveyard service";

    domain = mkOption {
      type = types.str;
      description = "Domain name for the graveyard service";
      example = "graveyard.example.com";
    };

    databaseSocket = mkOption {
      type = types.str;
      default = "/run/postgresql";
      description = "PostgreSQL unix socket directory";
    };

    jwtSecret = mkOption {
      type = types.str;
      description = "JWT secret for PostgREST authentication";
      example = "DL+P8+muauKgOSqRKqIKMkjcUpLZ5ajXScgA965i/Bg=";
    };

    accessLog = mkOption {
      type = types.str;
      default = "/var/log/nginx/graveyard.access.log";
      description = "Access log path for the graveyard virtual host";
    };

    admin = mkOption {
      type = types.submodule {
        options = {
          email = mkOption {
            type = types.str;
            description = "Admin user email for back-office login";
            example = "admin@example.com";
          };
          password = mkOption {
            type = types.str;
            description = "Admin user password for back-office login";
            example = "secure-password-here";
          };
        };
      };
      description = "Admin user credentials for back-office access";
    };
  };

  config = mkIf cfg.enable {
    users.users.graveyard = {
      isSystemUser = true;
      group = "web";
      home = dataDir;
      createHome = true;
      description = "Graveyard service user";
    };
    users.groups.web = { };


    systemd.services.graveyard = {
      description = "Graveyard PostgREST service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "graveyard-migrate.service" ];
      requires = [ "graveyard-migrate.service" ];

      serviceConfig = {
        Type = "simple";
        User = serviceName;
        Group = "web";

        ExecStart = "${pkgs.postgrest}/bin/postgrest ${postgrestConf}";

        Restart = "on-failure";
        RestartSec = "5s";

        # Security
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = [ dataDir ];
        RuntimeDirectory = serviceName;
        RuntimeDirectoryMode = "0755";
      };
    };


    services.postgresql = {
      package = pkgs.postgresql_17;
      enable = true;
      enableTCPIP = false;
      extensions = ps: with ps; [ pgjwt ];
      ensureDatabases = [ serviceName ];
      ensureUsers = [
        {
          name = serviceName;
          ensureDBOwnership = true;
        }
        {
          name = "authenticator";
          ensureClauses = {
            login = true;
            "inherit" = false;
          };
        }
      ];
    };


    systemd.services.graveyard-migrate = {
      description = "Run graveyard database migrations";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        echo "Running goose migrations..."
        ${goose}/bin/goose -dir ${migrationsDir} postgres "host=${cfg.databaseSocket} dbname=${serviceName} sslmode=disable" up

        echo "Setting JWT secret from configuration..."
        ${config.services.postgresql.package}/bin/psql -d ${serviceName} -c "ALTER DATABASE ${serviceName} SET app.jwt_secret = '${cfg.jwtSecret}';"

        echo "Granting roles to ${serviceName} user for PostgREST..."
        ${config.services.postgresql.package}/bin/psql -d ${serviceName} -c "GRANT anonymous TO ${serviceName} WITH INHERIT FALSE, SET TRUE;" || true
        ${config.services.postgresql.package}/bin/psql -d ${serviceName} -c "GRANT submitter TO ${serviceName} WITH INHERIT FALSE, SET TRUE;" || true
        ${config.services.postgresql.package}/bin/psql -d ${serviceName} -c "GRANT admin TO ${serviceName} WITH INHERIT FALSE, SET TRUE;" || true

        echo "Creating admin user..."
        ${config.services.postgresql.package}/bin/psql -d ${serviceName} -c "INSERT INTO graveyard.users (email, password) VALUES ('${cfg.admin.email}', crypt('${cfg.admin.password}', gen_salt('bf'))) ON CONFLICT (email) DO UPDATE SET password = EXCLUDED.password;"

        echo "Database migrations completed"
      '';
    };


    services.nginx = {
      enable = true;
      package = pkgs.openresty;

      virtualHosts."${cfg.domain}" = {
        forceSSL = true;
        enableACME = true;

        extraConfig = ''
          access_log ${cfg.accessLog};
          client_max_body_size 10M;
        '';

        locations."/" = {
          root = mainStaticBundle;
          tryFiles = "$uri $uri/ /index.html";
        };

        locations."/back-office/" = {
          alias = "${backOfficeBundle}/";
          tryFiles = "$uri $uri/ /back-office/index.html";
        };

        locations."/api/" = {
          proxyPass = "http://unix:${postgrestSocket}:/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;

            access_by_lua_block {
              local headers = ngx.req.get_headers()
              local auth_header = headers["Authorization"]
              local cookie_value = headers["Cookie"] or ""
              local auth_cookie = cookie_value:match("authorization=([^;]+)")

              if auth_header and not auth_cookie then
                ngx.ctx.set_auth_cookie = auth_header
              elseif not auth_header and auth_cookie then
                ngx.req.set_header("Authorization", auth_cookie)
              end
            }

            header_filter_by_lua_block {
              if ngx.ctx.set_auth_cookie then
                ngx.header["Set-Cookie"] = "authorization=" .. ngx.ctx.set_auth_cookie .. "; Path=/; Secure; HttpOnly"
              end
            }
          '';
        };
      };
    };

    users.users.nginx.extraGroups = [ "web" "acme" ];
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
