{
  description = "Graveyard - Elm + PostgreSQL + PostgREST + Nginx application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Import modules
        postgres = import ./nix/postgres.nix { inherit pkgs; };
        postgrest = import ./nix/postgrest.nix { inherit pkgs; };
        staticAssets = import ./nix/static-assets.nix { inherit pkgs; };
        elmWatch = import ./nix/elm-watch.nix { inherit pkgs; };
        nginx = import ./nix/nginx.nix { inherit pkgs; };
        scripts = import ./nix/scripts.nix {
          inherit pkgs;
          postgresql = postgres.postgresql;
        };
      in
      {
        # Export packages
        packages = {
          inherit (staticAssets) icono milligram postgrestAdmin;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ elmPackages.elm ]
          ++ postgres.buildInputs
          ++ postgres.scripts
          ++ postgrest.buildInputs
          ++ postgrest.scripts
          ++ nginx.buildInputs
          ++ nginx.scripts
          ++ scripts.scripts;

          shellHook = ''
            export PGDATA=$PWD/database/pgdata
            export PGHOST=$PWD/database/pgdata
            export PGDATABASE=graveyard

            # Add elm-watch from nix to PATH
            export PATH="${elmWatch.nodeModules}/node_modules/.bin:$PATH"

            # Setup static assets for back-office
            mkdir -p "$PWD/back-office/static"
            cp -f "${staticAssets.icono}/icono.min.css" "$PWD/back-office/static/icono.min.css"
            cp -f "${staticAssets.milligram}/milligram.min.css" "$PWD/back-office/static/milligram.min.css"

            echo "Graveyard - Development Environment"
            echo "PostgreSQL data dir: $PGDATA"
            echo ""
            echo ""
            echo "Available commands:"
            echo "  setup           - Initialize database and load dump (run this first)"
            echo "  run [port]      - Start all services, default port 4000"
            echo "  run-postgres    - Start PostgreSQL service only"
            echo "  run-postgrest   - Start PostgREST service only"
            echo "  run-nginx       - Start Nginx service only"
            echo "  load-dump       - Reload schema into database"
            echo "  database        - Open database shell (psql)"
            echo "  stop            - Stop all services"
            echo "  clean           - Remove database and start fresh"
          '';
        };
      });
}
