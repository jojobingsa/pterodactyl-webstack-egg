# Pterodactyl All-in-One Webstack Egg

Enthalten:

- Nginx
- PHP-FPM 8.4 + gängige PHP-Module
- Composer
- MariaDB
- phpMyAdmin 5.2.3
- persistente Website unter `/home/container/www`
- persistente Datenbank unter `/home/container/mysql`

## Warum zusätzlich ein Docker-Image?

Ein Pterodactyl-Egg kann beim Installieren Dateien unter `/home/container` vorbereiten, aber Betriebssystem-Pakete, die nur im separaten Installer-Container installiert werden, stehen dem späteren Runtime-Container nicht automatisch zur Verfügung. Darum enthält dieses Paket ein eigenes Pterodactyl-kompatibles Docker-Image.

## Variante A: über GitHub Container Registry (am einfachsten)

1. Neues GitHub-Repository erstellen.
2. Alle Dateien dieses Ordners hochladen.
3. GitHub Actions aktivieren und den Workflow einmal laufen lassen.
4. Danach existiert das Image als:
   `ghcr.io/DEIN_GITHUB_NAME/pterodactyl-webstack:latest`
5. In `egg-nginx-php-mariadb-phpmyadmin.json` den Wert
   `ghcr.io/jojobingsa/pterodactyl-webstack-egg:latest`
   durch deine Image-URL ersetzen.
6. Egg im Pterodactyl Admin Panel importieren.

Wenn das GitHub-Package privat ist, muss die Registry in Wings hinterlegt werden. Für einen einfachen Start das Container-Package öffentlich stellen.

## Variante B: Image auf dem Pterodactyl-Node lokal bauen

Im Ordner mit dem Dockerfile:

```bash
docker build -t pterodactyl-webstack:latest .
```

Danach im Egg die Docker-Image-URL auf `pterodactyl-webstack:latest` ändern. Je nach Wings-Pull-Konfiguration ist eine Registry trotzdem die zuverlässigere Variante.

## Pterodactyl

Import:

`Admin Panel -> Nests -> Import Egg`

Beim Erstellen des Servers muss die primäre Allocation der HTTP-Port sein. Nginx lauscht automatisch auf `SERVER_PORT`.

### Standardwerte

- Website: `/home/container/www`
- MariaDB Host für PHP: `127.0.0.1`
- MariaDB Port: `3306`
- Datenbank: `website`
- Datenbankbenutzer: `website`
- phpMyAdmin: `http://SERVER:PORT/phpmyadmin/`

Die beiden Standardpasswörter unbedingt vor dem ersten Start ändern.

### Beispiel PHP-Verbindung

```php
<?php
$pdo = new PDO(
    'mysql:host=127.0.0.1;port=3306;dbname=website;charset=utf8mb4',
    'website',
    'DEIN_DB_PASSWORT',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
```

## Sicherheit

MariaDB bindet nur an `127.0.0.1:3306` im Container. Der Datenbank-Port wird dadurch nicht öffentlich freigegeben. phpMyAdmin ist hingegen über den Web-Port erreichbar; ändere deshalb `PMA_PATH` auf einen schwer erratbaren Pfad oder setze `PMA_ENABLED=0`, wenn du es nicht brauchst.

Für eine öffentliche Website sollte TLS/HTTPS vor dem Pterodactyl-Port über einen Reverse Proxy (z. B. Host-Nginx, Caddy oder Cloudflare Tunnel) terminieren.


## v3 PATH / stale-script verification

This revision also publishes `:v3` and deliberately disables the Docker build
cache. The image build fails if `/usr/local/bin/ptero-webstack` does not contain
the `MARIADBD_BIN` lookup.

After GitHub Actions succeeds, verify the image with:

```bash
docker pull ghcr.io/jojobingsa/pterodactyl-webstack:v3
docker run --rm --entrypoint /bin/bash ghcr.io/jojobingsa/pterodactyl-webstack:v3 -lc \
  'echo "$PATH"; command -v mariadbd; mariadbd --version; grep -n "MARIADBD_BIN" /usr/local/bin/ptero-webstack | head'
```

For the first test, point the Pterodactyl egg at:

`ghcr.io/jojobingsa/pterodactyl-webstack:v3`

This avoids ambiguity about an older `latest` manifest.
