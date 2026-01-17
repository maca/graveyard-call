{ pkgs }:

let
  goose = pkgs.goose;
  migrationsDir = ../../database/migrations;

  postgresql = pkgs.postgresql_17.withPackages (ps: [ ps.pgjwt ]);
  serviceName = "graveyard";
  devJwtSecret = "DL+P8+muauKgOSqRKqIKMkjcUpLZ5ajXScgA965i/Bg=";

  pgEnvSetup = ''
    export PGDATA=$PWD/database/pgdata
    export PGHOST=$PWD/database/pgdata
    export PGDATABASE=${serviceName}
  '';

  pgHelpers = ''
    pg_is_running() {
      ${postgresql}/bin/pg_ctl -D "$PGDATA" status > /dev/null 2>&1
    }

    pg_start() {
      ${postgresql}/bin/pg_ctl \
        -D "$PGDATA" \
        -o "-k $PGHOST" \
        -l "$PGDATA/postgresql.log" \
        start
      sleep 3
    }

    pg_stop() {
      ${postgresql}/bin/pg_ctl -D "$PGDATA" stop
    }

    pg_get_pid() {
      ${postgresql}/bin/pg_ctl -D "$PGDATA" status | \
        grep -o 'PID: [0-9]*' | cut -d' ' -f2
    }
  '';

  setup = pkgs.writeShellScriptBin "setup" ''
    echo "Setting up database..."

    ${pgEnvSetup}
    ${pgHelpers}

    # Initialize PostgreSQL if it doesn't exist
    if [ ! -f "$PGDATA/PG_VERSION" ]; then
      echo "Initializing PostgreSQL database..."
      mkdir -p "$PGDATA"
      ${postgresql}/bin/initdb \
        -D "$PGDATA" \
        --auth-local=trust \
        --auth-host=trust
    else
      echo "PostgreSQL data directory already exists"
    fi

    # Start PostgreSQL temporarily if not running
    STARTED_POSTGRES=false
    if ! pg_is_running; then
      echo "Starting PostgreSQL temporarily for setup..."
      pg_start
      STARTED_POSTGRES=true
    fi

    # Create database if it doesn't exist
    if ! ${postgresql}/bin/psql \
         --host="$PGHOST" \
         -d postgres \
         -lqt | cut -d \| -f 1 | grep -qw ${serviceName}; then
      echo "Creating ${serviceName} database..."
      ${postgresql}/bin/createdb ${serviceName} --host="$PGHOST"
    else
      echo "Database '${serviceName}' already exists"
    fi

    # Run goose migrations
    echo "Running goose migrations..."
    GOOSE_DRIVER=postgres \
    GOOSE_DBSTRING="host=$PGHOST dbname=${serviceName} sslmode=disable" \
    GOOSE_MIGRATION_DIR=${migrationsDir} \
      ${goose}/bin/goose up

    # Set JWT secret
    echo "Setting JWT secret..."
    ${postgresql}/bin/psql --host="$PGHOST" -d ${serviceName} \
      -c "ALTER DATABASE ${serviceName} SET app.jwt_secret = '${devJwtSecret}';"

    # Create dev user
    echo "Creating dev user..."
    ${postgresql}/bin/psql --host="$PGHOST" -d ${serviceName} \
      -c "INSERT INTO graveyard.users (email, password) VALUES ('user@example.com', crypt('password', gen_salt('bf'))) ON CONFLICT (email) DO NOTHING;"

    # Stop PostgreSQL if we started it
    if [ "$STARTED_POSTGRES" = true ]; then
      echo "Stopping temporary PostgreSQL instance..."
      pg_stop
    fi

    echo ""
    echo "Setup completed successfully!"
    echo "Run 'run' to start the services"
  '';

  run-postgres = pkgs.writeShellScriptBin "run-postgres" ''
    echo "Starting PostgreSQL..."

    ${pgEnvSetup}
    ${pgHelpers}

    # Check if setup has been run
    if [ ! -f "$PGDATA/PG_VERSION" ]; then
      echo "Error: PostgreSQL not initialized. Run 'setup' first."
      exit 1
    fi

    # Start PostgreSQL if not already running
    if pg_is_running; then
      echo "PostgreSQL is already running"
      POSTGRES_PID=$(pg_get_pid)
    else
      echo "Starting PostgreSQL..."
      pg_start
      POSTGRES_PID=$(pg_get_pid)

      # Start PostgreSQL log tailer
      echo "Starting PostgreSQL log monitor..."
      tail -f "$PGDATA/postgresql.log" 2>/dev/null &
      LOG_TAILER_PID=$!
    fi

    echo "PostgreSQL service started successfully"
    echo "Database: ${serviceName}"
    echo "Socket: $PGHOST/.s.PGSQL.5432"
    echo "Connection: postgres:///?host=$PGHOST&dbname=${serviceName}"
    echo "PostgreSQL PID: $POSTGRES_PID"

    # Trap to cleanup PostgreSQL on exit
    cleanup() {
      echo "Stopping PostgreSQL..."
      if [ -n "$LOG_TAILER_PID" ] && kill -0 "$LOG_TAILER_PID" 2>/dev/null; then
        kill "$LOG_TAILER_PID" 2>/dev/null
      fi
      if [ -d "$PGDATA" ] && pg_is_running; then
        pg_stop
      fi
      exit
    }

    trap cleanup INT TERM

    # Keep the script running
    if [ -n "$LOG_TAILER_PID" ]; then
      wait $LOG_TAILER_PID
    else
      while kill -0 "$POSTGRES_PID" 2>/dev/null; do
        sleep 1
      done
    fi
  '';

  database = pkgs.writeShellScriptBin "database" ''
    ${pgEnvSetup}

    echo "Connecting to database: ${serviceName}"
    exec ${postgresql}/bin/psql --host="$PGHOST" -d ${serviceName}
  '';

in
{
  inherit postgresql goose;
  scripts = [ setup run-postgres database ];
  buildInputs = [ postgresql goose ];
}
