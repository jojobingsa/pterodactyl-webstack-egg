#!/bin/bash
set -e
cd /home/container

# Pterodactyl passes the egg startup command through STARTUP.
MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP:-/usr/local/bin/ptero-webstack}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
echo ":/home/container$ ${MODIFIED_STARTUP}"
exec /bin/bash -lc "${MODIFIED_STARTUP}"
