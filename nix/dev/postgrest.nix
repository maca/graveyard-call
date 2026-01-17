{ pkgs }:

let
  # Generate postgrest.conf based on environment
  postgrestConf = pkgs.writeText "postgrest.conf" ''
    # db-uri is set via PGRST_DB_URI environment variable in run-postgrest script
    db-uri = "postgres:///?host=database/pgdata&dbname=graveyard"
    db-schemas = "graveyard"
    db-anon-role = "anonymous"
    jwt-secret = "DL+P8+muauKgOSqRKqIKMkjcUpLZ5ajXScgA965i/Bg="
    server-unix-socket = "/tmp/postgrest-graveyard.sock"
  '';

  run-postgrest = pkgs.writeShellScriptBin "run-postgrest" ''
    echo "Starting PostgREST..."

    # Remove existing socket if it exists
    rm -f /tmp/postgrest-graveyard.sock

    # Set PGRST_DB_URI environment variable to override db-uri in config
    export PGRST_DB_URI="postgres:///?host=$PWD/database/pgdata&dbname=graveyard"

    ${pkgs.postgrest}/bin/postgrest ${postgrestConf} &
    POSTGREST_PID=$!

    cleanup() {
      echo "Stopping PostgREST..."
      if kill -0 "$POSTGREST_PID" 2>/dev/null; then
        kill "$POSTGREST_PID" 2>/dev/null
      fi
      rm -f /tmp/postgrest-graveyard.sock
      exit
    }

    trap cleanup INT TERM

    echo "PostgREST started with PID: $POSTGREST_PID"
    echo "Socket: /tmp/postgrest-graveyard.sock"
    wait $POSTGREST_PID
  '';

in
{
  scripts = [ run-postgrest ];
  buildInputs = [ pkgs.postgrest ];
}
