#!/usr/bin/env bash
# Publica la versión nueva del proyecto: baja el código, instala dependencias,
# migra y REINICIA PHP. El reinicio es obligatorio: OPcache corre con
# validate_timestamps=0 y sin él seguiría sirviendo el código anterior.
#   ./scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICIO=orthoshoefix
PROYECTO=orthoshoefix

git -C "projects/$PROYECTO" pull --ff-only

run() { docker compose exec -T -e COMPOSER_HOME=/tmp/composer -e npm_config_cache=/tmp/npm "$SERVICIO" "$@"; }

run composer install --no-dev --optimize-autoloader --no-interaction
if [ -f "projects/$PROYECTO/package.json" ]; then
    run sh -c 'npm ci && npm run build'
fi
run php artisan migrate --force
run php artisan optimize

docker compose restart "$SERVICIO"
echo "OK: $PROYECTO publicado y $SERVICIO reiniciado."
