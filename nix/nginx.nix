{ pkgs }:

let
  # Nginx configuration for development
  nginxConf = pkgs.writeText "nginx.conf" ''
    daemon off;
    error_log stderr;
    pid /tmp/nginx-graveyard.pid;

    events {
      worker_connections 1024;
    }

    http {
      client_max_body_size 10M;  # Increase to your needs
      include ${pkgs.nginx}/conf/mime.types;
      default_type application/octet-stream;

      access_log /dev/stdout;

      client_body_temp_path /tmp/nginx-client-body;
      proxy_temp_path /tmp/nginx-proxy;
      fastcgi_temp_path /tmp/nginx-fastcgi;
      uwsgi_temp_path /tmp/nginx-uwsgi;
      scgi_temp_path /tmp/nginx-scgi;

      server {
        listen 4000;
        server_name localhost;

        location / {
          proxy_pass http://localhost:8000;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_read_timeout 86400;
        }

        location /back-office/ {
          alias BACK_OFFICE_PATH/;
          try_files $uri $uri/ /back-office/index.html;
        }

        location /api/ {
          proxy_pass http://unix:/tmp/postgrest-graveyard.sock:/;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        }
      }
    }
  '';

  run-nginx = pkgs.writeShellScriptBin "run-nginx" ''
    echo "Starting Nginx..."

    # Create temp directories
    mkdir -p /tmp/nginx-client-body /tmp/nginx-proxy /tmp/nginx-fastcgi /tmp/nginx-uwsgi /tmp/nginx-scgi

    # Replace placeholder paths in nginx config
    NGINX_CONF=$(mktemp)
    sed "s|BACK_OFFICE_PATH|$PWD/back-office/static|g; s|SUBMISSIONS_PATH|$PWD/static|g" ${nginxConf} > "$NGINX_CONF"

    # Start nginx (redirect stderr to suppress default error log warning)
    ${pkgs.nginx}/bin/nginx -c "$NGINX_CONF" 2>&1 | grep -v "could not open error log file" | grep -v "nginx: \[alert\]" &
    NGINX_PID=$!

    cleanup() {
      echo "Stopping Nginx..."
      if kill -0 "$NGINX_PID" 2>/dev/null; then
        kill "$NGINX_PID" 2>/dev/null
      fi
      rm -f /tmp/nginx-graveyard.pid "$NGINX_CONF"
      exit
    }

    trap cleanup INT TERM

    echo "Nginx started with PID: $NGINX_PID"
    echo "Listening on http://localhost:4000"
    echo "  - Back-office: http://localhost:4000/back-office/"
    echo "  - Submissions: http://localhost:4000/"
    echo "  - API: http://localhost:4000/api/"
    wait $NGINX_PID
  '';

in
{
  scripts = [ run-nginx ];
  buildInputs = [ pkgs.nginx ];
}
