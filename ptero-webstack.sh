#!/bin/bash
set -Eeuo pipefail

HOME_DIR="/home/container"
WEBROOT="${HOME_DIR}/www"
DB_DIR="${HOME_DIR}/mysql"
RUN_DIR="${HOME_DIR}/.run"
CFG_DIR="${HOME_DIR}/.config"
CACHE_DIR="${HOME_DIR}/.cache"
MYSQL_SOCKET="${RUN_DIR}/mysql.sock"
MYSQL_PID_FILE="${RUN_DIR}/mariadb.pid"

SERVER_PORT="${SERVER_PORT:-8080}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-ChangeMeRoot123!}"
DB_NAME="${DB_NAME:-website}"
DB_USER="${DB_USER:-website}"
DB_PASSWORD="${DB_PASSWORD:-ChangeMeApp123!}"
PMA_PATH="${PMA_PATH:-phpmyadmin}"
PMA_ENABLED="${PMA_ENABLED:-1}"
PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-256M}"
UPLOAD_MAX_FILESIZE="${UPLOAD_MAX_FILESIZE:-128M}"
POST_MAX_SIZE="${POST_MAX_SIZE:-128M}"
MAX_EXECUTION_TIME="${MAX_EXECUTION_TIME:-120}"
TZ="${TZ:-Europe/Berlin}"

MYSQL_PID=""
PHP_PID=""
NGINX_PID=""

log() { printf '[webstack] %s\n' "$*"; }
fatal() { printf '[webstack] ERROR: %s\n' "$*" >&2; exit 1; }

validate() {
    [[ "$SERVER_PORT" =~ ^[0-9]{1,5}$ ]] || fatal "SERVER_PORT is invalid"
    (( SERVER_PORT >= 1 && SERVER_PORT <= 65535 )) || fatal "SERVER_PORT out of range"
    [[ "$DB_NAME" =~ ^[A-Za-z0-9_]{1,32}$ ]] || fatal "DB_NAME may only contain A-Z, a-z, 0-9 and _"
    [[ "$DB_USER" =~ ^[A-Za-z0-9_]{1,32}$ ]] || fatal "DB_USER may only contain A-Z, a-z, 0-9 and _"
    [[ "$PMA_PATH" =~ ^[A-Za-z0-9_-]{1,40}$ ]] || fatal "PMA_PATH may only contain A-Z, a-z, 0-9, _ and -"
    [[ "$DB_ROOT_PASSWORD" =~ ^[A-Za-z0-9._@#%+=!-]{8,64}$ ]] || fatal "DB_ROOT_PASSWORD contains unsupported characters or is too short"
    [[ "$DB_PASSWORD" =~ ^[A-Za-z0-9._@#%+=!-]{8,64}$ ]] || fatal "DB_PASSWORD contains unsupported characters or is too short"
}

cleanup() {
    trap - EXIT INT TERM
    log "Stopping services..."
    if [[ -n "${NGINX_PID}" ]] && kill -0 "$NGINX_PID" 2>/dev/null; then kill -TERM "$NGINX_PID" 2>/dev/null || true; fi
    if [[ -n "${PHP_PID}" ]] && kill -0 "$PHP_PID" 2>/dev/null; then kill -TERM "$PHP_PID" 2>/dev/null || true; fi
    if [[ -S "$MYSQL_SOCKET" ]]; then
        local stored=""
        [[ -f "${HOME_DIR}/.db-root-password" ]] && stored="$(cat "${HOME_DIR}/.db-root-password")"
        if [[ -n "$stored" ]]; then
            mariadb-admin --protocol=socket --socket="$MYSQL_SOCKET" -uroot -p"$stored" shutdown >/dev/null 2>&1 || true
        fi
    fi
    if [[ -n "${MYSQL_PID}" ]] && kill -0 "$MYSQL_PID" 2>/dev/null; then kill -TERM "$MYSQL_PID" 2>/dev/null || true; fi
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

validate
mkdir -p "$WEBROOT" "$DB_DIR" "$RUN_DIR" "$CFG_DIR/nginx" "$CFG_DIR/php.d" "$CACHE_DIR/nginx/client_temp" "$CACHE_DIR/nginx/proxy_temp" "$CACHE_DIR/nginx/fastcgi_temp" "$CACHE_DIR/nginx/uwsgi_temp" "$CACHE_DIR/nginx/scgi_temp" "$CACHE_DIR/phpmyadmin"

if [[ ! -f "${HOME_DIR}/.pma-secret" ]]; then
    openssl rand -hex 32 > "${HOME_DIR}/.pma-secret"
    chmod 600 "${HOME_DIR}/.pma-secret"
fi

# Create or update the phpMyAdmin symlink inside the web root.
OLD_PMA_PATH=""
[[ -f "${HOME_DIR}/.pma-path" ]] && OLD_PMA_PATH="$(cat "${HOME_DIR}/.pma-path")"
if [[ -n "$OLD_PMA_PATH" && "$OLD_PMA_PATH" != "$PMA_PATH" && -L "$WEBROOT/$OLD_PMA_PATH" ]]; then
    rm -f "$WEBROOT/$OLD_PMA_PATH"
fi
if [[ "$PMA_ENABLED" == "1" ]]; then
    if [[ -e "$WEBROOT/$PMA_PATH" && ! -L "$WEBROOT/$PMA_PATH" ]]; then
        fatal "$WEBROOT/$PMA_PATH already exists and is not a symlink. Choose another PMA_PATH."
    fi
    ln -sfn /opt/phpmyadmin "$WEBROOT/$PMA_PATH"
    printf '%s' "$PMA_PATH" > "${HOME_DIR}/.pma-path"
else
    [[ -L "$WEBROOT/$PMA_PATH" ]] && rm -f "$WEBROOT/$PMA_PATH"
fi

if [[ ! -e "$WEBROOT/index.php" && ! -e "$WEBROOT/index.html" ]]; then
    cat > "$WEBROOT/index.php" <<'PHP'
<?php
header('Content-Type: text/html; charset=UTF-8');
?>
<!doctype html>
<html lang="de">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Pterodactyl Webstack</title></head>
<body style="font-family:system-ui;max-width:760px;margin:60px auto;padding:0 20px;line-height:1.5">
<h1>✅ Webstack läuft</h1>
<p>Nginx, PHP-FPM und MariaDB wurden erfolgreich gestartet.</p>
<p>Lege deine Website in <code>/home/container/www</code> ab.</p>
</body>
</html>
PHP
fi

cat > "$CFG_DIR/php.d/99-pterodactyl.ini" <<EOF_PHPINI
memory_limit=${PHP_MEMORY_LIMIT}
upload_max_filesize=${UPLOAD_MAX_FILESIZE}
post_max_size=${POST_MAX_SIZE}
max_execution_time=${MAX_EXECUTION_TIME}
date.timezone=${TZ}
display_errors=Off
log_errors=On
expose_php=Off
session.save_path="${HOME_DIR}/.cache"
EOF_PHPINI

cat > "$CFG_DIR/php-fpm.conf" <<EOF_FPM
[global]
pid = ${RUN_DIR}/php-fpm.pid
error_log = /proc/self/fd/2
daemonize = no

[www]
listen = ${RUN_DIR}/php-fpm.sock
listen.mode = 0660
pm = dynamic
pm.max_children = 16
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 4
pm.max_requests = 500
catch_workers_output = yes
clear_env = no
chdir = ${WEBROOT}
EOF_FPM

cat > "$CFG_DIR/nginx/nginx.conf" <<EOF_NGINX
pid ${RUN_DIR}/nginx.pid;
error_log /dev/stderr warn;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /dev/stdout;
    sendfile on;
    keepalive_timeout 65;
    server_tokens off;
    client_max_body_size ${POST_MAX_SIZE};

    client_body_temp_path ${CACHE_DIR}/nginx/client_temp;
    proxy_temp_path ${CACHE_DIR}/nginx/proxy_temp;
    fastcgi_temp_path ${CACHE_DIR}/nginx/fastcgi_temp;
    uwsgi_temp_path ${CACHE_DIR}/nginx/uwsgi_temp;
    scgi_temp_path ${CACHE_DIR}/nginx/scgi_temp;

    server {
        listen 0.0.0.0:${SERVER_PORT};
        server_name _;
        root ${WEBROOT};
        index index.php index.html index.htm;

        location / {
            try_files \$uri \$uri/ /index.php?\$query_string;
        }

        location ~ \.php$ {
            try_files \$uri =404;
            include /etc/nginx/fastcgi_params;
            fastcgi_pass unix:${RUN_DIR}/php-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param HTTP_PROXY "";
        }

        location ~ /\. {
            deny all;
        }
    }
}
EOF_NGINX

export PHP_INI_SCAN_DIR="/etc/php/8.4/fpm/conf.d:${CFG_DIR}/php.d"

FIRST_INIT=0
if [[ ! -d "$DB_DIR/mysql" ]]; then
    FIRST_INIT=1
    log "Initializing MariaDB data directory..."
    mariadb-install-db \
        --datadir="$DB_DIR" \
        --auth-root-authentication-method=normal \
        --skip-test-db >/dev/null
fi

start_mariadb() {
    mariadbd \
        --datadir="$DB_DIR" \
        --socket="$MYSQL_SOCKET" \
        --pid-file="$MYSQL_PID_FILE" \
        --port=3306 \
        --bind-address=127.0.0.1 \
        --skip-name-resolve \
        --max-connections=100 \
        --character-set-server=utf8mb4 \
        --collation-server=utf8mb4_unicode_ci \
        --log-error=/dev/stderr &
    MYSQL_PID=$!
}

wait_for_mariadb_noauth() {
    for _ in $(seq 1 60); do
        [[ -S "$MYSQL_SOCKET" ]] && mariadb-admin --protocol=socket --socket="$MYSQL_SOCKET" ping >/dev/null 2>&1 && return 0
        kill -0 "$MYSQL_PID" 2>/dev/null || return 1
        sleep 0.5
    done
    return 1
}

wait_for_mariadb_auth() {
    local password="$1"
    for _ in $(seq 1 60); do
        [[ -S "$MYSQL_SOCKET" ]] && mariadb-admin --protocol=socket --socket="$MYSQL_SOCKET" -uroot -p"$password" ping >/dev/null 2>&1 && return 0
        kill -0 "$MYSQL_PID" 2>/dev/null || return 1
        sleep 0.5
    done
    return 1
}

if (( FIRST_INIT == 1 )); then
    log "Configuring initial MariaDB users..."
    mariadbd \
        --datadir="$DB_DIR" \
        --socket="$MYSQL_SOCKET" \
        --pid-file="$MYSQL_PID_FILE" \
        --skip-networking \
        --skip-name-resolve \
        --log-error=/dev/stderr &
    MYSQL_PID=$!
    wait_for_mariadb_noauth || fatal "MariaDB failed during initial setup"

    mariadb --protocol=socket --socket="$MYSQL_SOCKET" -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    printf '%s' "$DB_ROOT_PASSWORD" > "${HOME_DIR}/.db-root-password"
    chmod 600 "${HOME_DIR}/.db-root-password"
    mariadb-admin --protocol=socket --socket="$MYSQL_SOCKET" -uroot -p"$DB_ROOT_PASSWORD" shutdown >/dev/null
    wait "$MYSQL_PID" 2>/dev/null || true
    MYSQL_PID=""
fi

STORED_ROOT_PASSWORD="$DB_ROOT_PASSWORD"
[[ -f "${HOME_DIR}/.db-root-password" ]] && STORED_ROOT_PASSWORD="$(cat "${HOME_DIR}/.db-root-password")"

log "Starting MariaDB..."
start_mariadb
wait_for_mariadb_auth "$STORED_ROOT_PASSWORD" || fatal "MariaDB failed to start or the stored root password is invalid"

# Keep egg variables authoritative on later starts too.
if ! mariadb --protocol=socket --socket="$MYSQL_SOCKET" -uroot -p"$STORED_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
    fatal "Stored MariaDB root password no longer works. If you changed it manually, restore .db-root-password or the database password."
fi

mariadb --protocol=socket --socket="$MYSQL_SOCKET" -uroot -p"$STORED_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
printf '%s' "$DB_ROOT_PASSWORD" > "${HOME_DIR}/.db-root-password"
chmod 600 "${HOME_DIR}/.db-root-password"

log "Starting PHP-FPM 8.4..."
php-fpm8.4 -F -y "$CFG_DIR/php-fpm.conf" &
PHP_PID=$!

for _ in $(seq 1 40); do
    [[ -S "$RUN_DIR/php-fpm.sock" ]] && break
    kill -0 "$PHP_PID" 2>/dev/null || fatal "PHP-FPM failed to start"
    sleep 0.25
done
[[ -S "$RUN_DIR/php-fpm.sock" ]] || fatal "PHP-FPM socket was not created"

log "Starting Nginx on port ${SERVER_PORT}..."
nginx -c "$CFG_DIR/nginx/nginx.conf" -g 'daemon off;' &
NGINX_PID=$!

sleep 0.5
kill -0 "$NGINX_PID" 2>/dev/null || fatal "Nginx failed to start"

log "Web stack ready"
log "Website: /home/container/www"
log "Database: ${DB_NAME} | User: ${DB_USER} | Host: 127.0.0.1 | Port: 3306"
if [[ "$PMA_ENABLED" == "1" ]]; then
    log "phpMyAdmin path: /${PMA_PATH}/"
fi

set +e
wait -n "$MYSQL_PID" "$PHP_PID" "$NGINX_PID"
STATUS=$?
set -e
fatal "A service exited unexpectedly (status ${STATUS})"
