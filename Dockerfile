FROM debian:13-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG PHPMYADMIN_VERSION=5.2.3

ENV USER=container \
    HOME=/home/container \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Prevent Debian packages from trying to start daemons during image build.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl git unzip tar gzip openssl procps \
       nginx mariadb-server mariadb-client \
       php8.4-fpm php8.4-cli php8.4-common php8.4-mysql php8.4-curl \
       php8.4-gd php8.4-mbstring php8.4-xml php8.4-zip php8.4-intl \
       php8.4-bcmath php8.4-soap php8.4-opcache php8.4-readline \
       composer \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -d /home/container -s /bin/bash container \
    && mkdir -p /opt/phpmyadmin \
    && curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz" \
       | tar -xz --strip-components=1 -C /opt/phpmyadmin \
    && rm -f /opt/phpmyadmin/config.sample.inc.php \
    && mkdir -p /home/container \
    && chown -R container:container /home/container

COPY phpmyadmin-config.inc.php /opt/phpmyadmin/config.inc.php
COPY entrypoint.sh /entrypoint.sh
COPY ptero-webstack.sh /usr/local/bin/ptero-webstack

# Pterodactyl can override PATH at runtime. Put daemon binaries in /usr/local/bin
# as well, so both old-style direct calls and the robust binary lookup work.
# The grep assertion intentionally fails the image build if an outdated
# ptero-webstack.sh is accidentally copied into the image.
RUN chmod 0755 /entrypoint.sh /usr/local/bin/ptero-webstack \
    && chmod 0644 /opt/phpmyadmin/config.inc.php \
    && ln -sf /usr/sbin/mariadbd /usr/local/bin/mariadbd \
    && ln -sf /usr/sbin/nginx /usr/local/bin/nginx \
    && ln -sf /usr/sbin/php-fpm8.4 /usr/local/bin/php-fpm8.4 \
    && test -x /usr/local/bin/mariadbd \
    && test -x /usr/local/bin/nginx \
    && test -x /usr/local/bin/php-fpm8.4 \
    && grep -q 'MARIADBD_BIN=' /usr/local/bin/ptero-webstack \
    && /usr/local/bin/mariadbd --version

USER container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
