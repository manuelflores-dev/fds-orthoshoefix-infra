# FDS Orthoshoefix — Infraestructura Docker (producción)

**Autor:** José Manuel Flores Hernández — Flores Dev Studio

Orquestación dedicada de **orthoshoefix.com**: un proyecto Laravel con su
propia base de datos.

Stack: PHP 8.5-FPM · Nginx · MariaDB 12.3 · Redis 8

Repo **específico de este proyecto**, con el mismo patrón que
`fds-natalia-infra`: un PHP-FPM por proyecto dentro de `projects/` y un Nginx
central con un `server{}` por dominio. La plantilla genérica reutilizable es
`flores-devstudio-infra`; esta no lo es.

## Estructura

```
fds-orthoshoefix-infra-docker/
├── docker-compose.yml
├── example.env               ← copiar a .env y configurar
├── .gitignore
├── docker-config/
│   ├── php/
│   │   └── orthoshoefix/
│   │       ├── Dockerfile    ← PHP 8.5 + extensiones Laravel + Node 24
│   │       └── php.ini
│   ├── nginx/                ← se monta completo como /etc/nginx/conf.d
│   │   ├── 00-default.conf   ← catch-all: Host desconocido → 444
│   │   └── orthoshoefix.conf ← server{} del proyecto
│   └── mariadb/
│       └── my.cnf
├── logs/nginx/               ← logs de Nginx (ignorado en git)
└── projects/             ← aquí se clona el proyecto (ignorado en git)
    └── orthoshoefix/
```

Este repo es **solo infraestructura**: `projects/` viaja vacío.

El nombre de carpeta `projects/orthoshoefix` es obligatorio: lo usan el volumen
del servicio y el `root` de nginx. Si algún día quieres meter un segundo
proyecto aquí, son tres cosas: un servicio en compose, un `.conf` en `docker-config/nginx/`
y su Dockerfile en `docker-config/php/<proyecto>/`.

## Convivencia con los otros stacks

Ningún namespace global se repite. Docker no prefija por proyecto los nombres
de contenedor ni el de la red, así que esto se cuida a mano:

|                | fds-orthoshoefix                | fds-natalia                |
|----------------|---------------------------------|----------------------------|
| Contenedores   | `orthoshoefix_*`                | `natalia_*`                |
| Red            | `orthoshoefix_network`          | `natalia_app_network`      |
| Volumen DB     | `fds-orthoshoefix_mariadb_data` | `fds-natalia_mariadb_data` |
| Nginx (host)   | `127.0.0.1:8081`                | `127.0.0.1:8082`           |
| MariaDB (host) | `127.0.0.1:33061`               | `127.0.0.1:33062`          |
| Redis          | sin publicar                    | sin publicar               |
| Zona horaria   | `America/Chicago`               | `America/Mexico_City`      |

El reparto por dominio lo hace `fds-server-proxy` (el nginx del host).

## Sobre los volúmenes

Docker prefija los volúmenes con el **nombre del proyecto compose**, que aquí
está fijado con `name: fds-orthoshoefix` en la primera línea de
`docker-compose.yml`. Quedan entonces como `fds-orthoshoefix_mariadb_data` y
`fds-orthoshoefix_redis_data`, sin importar cómo se llame la carpeta ni dónde
esté.

Sin ese `name:`, el prefijo lo pone la carpeta — y renombrarla crea un volumen
nuevo y vacío, con lo que parece que se borró la base de datos.

Ten presente que **`MARIADB_DATABASE`, `MARIADB_USER` y `MARIADB_PASSWORD` solo se
aplican cuando el volumen está vacío.** Si montas un volumen que ya tiene
datos, MariaDB los ignora y conserva los usuarios que ya tenía dentro. Para
cambiar credenciales sobre una base existente hay que hacerlo desde SQL:

```bash
docker compose exec db mariadb -u root -p -e "
ALTER USER 'orthoshoefix'@'%' IDENTIFIED BY 'nueva_password';
FLUSH PRIVILEGES;"
```

## Despliegue

### Empezar limpio (base de datos nueva)

```bash
# 1. Si venías del stack viejo, bájalo y borra sus volúmenes
cd <stack-viejo> && docker compose down -v

# 2. Configurar
git clone <repo> fds-orthoshoefix-infra
cd fds-orthoshoefix-infra
cp example.env .env
nano .env                 # contraseñas nuevas y fuertes

# 3. Clonar el proyecto — el nombre de carpeta es obligatorio
git clone <repo-laravel> projects/orthoshoefix

# 4. Levantar
docker compose up -d --build

# 5. Configurar Laravel
docker compose exec orthoshoefix composer install --no-dev --optimize-autoloader
docker compose exec orthoshoefix php artisan key:generate
docker compose exec orthoshoefix php artisan migrate --force
docker compose exec orthoshoefix php artisan storage:link
docker compose exec orthoshoefix npm ci
docker compose exec orthoshoefix npm run build
```

### Conservar una base existente

Igual que arriba, pero **sin la `-v`** en el paso 1 (la `-v` borra los
volúmenes) y verificando primero cómo se llama el volumen actual:

```bash
docker volume ls | grep mariadb
```

Si ese volumen no se llama `fds-orthoshoefix_mariadb_data`, ajusta el `name:`
de la primera línea del compose para que el prefijo coincida. Y respalda antes
de tocar nada:

```bash
docker compose exec db mariadb-dump -u root -p --single-transaction --all-databases > backup_$(date +%F).sql
```

## El .env de Laravel

Va en `projects/orthoshoefix/.env`. Los hosts son los **nombres de servicio**
de compose:

```dotenv
APP_ENV=production
APP_DEBUG=false
APP_URL=https://orthoshoefix.com
APP_TIMEZONE=America/Chicago

DB_CONNECTION=mariadb
DB_HOST=db
DB_PORT=3306
DB_DATABASE=orthoshoefix
DB_USERNAME=orthoshoefix
DB_PASSWORD=<el mismo del .env de la orquestación>

REDIS_CLIENT=phpredis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=<el mismo del .env de la orquestación>

CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
```

Ojo: el puerto `33061` del `.env` de la orquestación es solo para llegar a
MariaDB desde el host (túnel SSH, PhpStorm). Los contenedores siempre usan
`db:3306`.

## Zona horaria — America/Chicago

El cliente de este proyecto está en Chicago, así que **todo el stack corre en
`America/Chicago`**, no en la hora de México. Está fijado en tres lugares y los
tres tienen que coincidir:

| Dónde | Qué controla |
|---|---|
| `TZ` en los 4 servicios de `docker-compose.yml` | reloj del sistema en cada contenedor: logs de nginx, `NOW()` de MariaDB, cron |
| `date.timezone` en `docker-config/php/orthoshoefix/php.ini` | funciones de fecha de PHP |
| `APP_TIMEZONE` en el `.env` de Laravel | `Carbon`, `now()`, timestamps de Eloquent |

El tercero es el que se olvida: la `TZ` del contenedor **no** cambia la zona
horaria de Laravel. Sin `APP_TIMEZONE`, Laravel usa UTC aunque el contenedor
esté en Chicago, y terminas con horas que no cuadran entre la base y la
aplicación.

Verificar que los tres coinciden:

```bash
docker compose exec orthoshoefix date
docker compose exec orthoshoefix php -r "echo date_default_timezone_get(), PHP_EOL;"
docker compose exec orthoshoefix php artisan tinker --execute="echo now();"
docker compose exec db date
```

El stack de pastelería (`fds-natalia-infra`) sigue en `America/Mexico_City`:
son negocios distintos y cada uno lleva su propia hora.

### Confiar en el reverse proxy

Como el TLS lo termina el proxy del host, hay que decirle a Laravel que confíe
en él para que genere URLs `https://`. En `bootstrap/app.php`:

```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->trustProxies(at: '*');
})
```

## Comandos útiles

```bash
docker compose up -d              # levantar
docker compose down               # bajar (NUNCA con -v)
docker compose logs -f nginx      # logs de un servicio
docker compose exec orthoshoefix bash      # entrar al contenedor PHP
docker compose ps                 # estado
```

## Publicar cambios (deploy)

```bash
./scripts/deploy.sh
```

Baja el código del proyecto (`git pull`), corre `composer install --no-dev`,
compila los assets si hay `package.json`, `php artisan migrate --force` y
`php artisan optimize`, y **reinicia PHP**. Ese reinicio no es opcional: OPcache
corre con `validate_timestamps=0` y sin él PHP sigue sirviendo el código anterior.
Si alguna vez actualizas a mano, termina siempre con `docker compose restart orthoshoefix`.

## Respaldos

```bash
./scripts/backup-db.sh
```

Deja `backups/AAAA-MM-DD_HHMM.sql.gz` (ignorado en git) y borra los de más de
14 días (`DIAS=30 ./scripts/backup-db.sh` para cambiarlo). Para que corra solo,
todos los días a las 3:30, con `crontab -e` del usuario que maneja Docker:

```
30 3 * * * /ruta/a/fds-orthoshoefix-infra-docker/scripts/backup-db.sh >> /ruta/a/fds-orthoshoefix-infra-docker/backups/backup.log 2>&1
```

Un respaldo que solo vive en el mismo servidor no sirve si el servidor se pierde:
copia `backups/` a otro lado (otra máquina, un bucket) con `rsync` o `rclone`.

Restaurar:

```bash
gunzip -c backups/ARCHIVO.sql.gz | docker compose exec -T db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"'
```

## Logs

- `docker compose logs`: rotan solos (10 MB × 5 por contenedor, `x-logging` del compose).
- `logs/nginx/*.log`: los escribe el nginx del stack y hay que rotarlos con el
  logrotate del servidor. Una vez, desde la carpeta del repo:

```bash
sudo tee /etc/logrotate.d/fds-orthoshoefix > /dev/null <<EOF
$(pwd)/logs/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

`copytruncate` porque nginx corre dentro del contenedor y no se le puede mandar
la señal para reabrir el archivo.

## Notas de seguridad

- MariaDB y Nginx solo escuchan en `127.0.0.1`; Redis no se publica.
- Redis con `requirepass`.
- PHP-FPM corre como `www-data` (no-root), con `php.ini-production`,
  `expose_php=Off` y `display_errors=Off`.
- Nginx monta el código en **solo lectura**.
- Un `Host` que no sea `orthoshoefix.com` recibe 444.
- `/.well-known/` queda accesible a propósito: si se bloquea, se rompen los
  challenges ACME de Let's Encrypt.
- OPcache con `validate_timestamps=0`: `scripts/deploy.sh` reinicia PHP al final
  de cada publicación (ver *Publicar cambios*).
- Logs de Docker con tope de tamaño y respaldos diarios de la base (ver arriba).
