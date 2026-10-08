#!/usr/bin/env bash
# Respaldo de la base de datos: dump comprimido en backups/ y borra los de más
# de DIAS días (14 por defecto). Pensado para cron; ver README → Respaldos.
#   ./scripts/backup-db.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DIAS=${DIAS:-14}
mkdir -p backups
ARCHIVO="backups/$(date +%F_%H%M).sql.gz"

docker compose exec -T db sh -c \
  'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --triggers --events --databases "$MARIADB_DATABASE"' \
  | gzip > "$ARCHIVO.tmp"
mv "$ARCHIVO.tmp" "$ARCHIVO"
chmod 600 "$ARCHIVO"

# Solo archivos .sql.gz dentro de backups/ con más de DIAS días
find backups -maxdepth 1 -type f -name '*.sql.gz' -mtime +"$DIAS" -delete
echo "OK: $ARCHIVO ($(du -h "$ARCHIVO" | cut -f1))"
