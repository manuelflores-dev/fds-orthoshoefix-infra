FROM php:8.5-fpm

#  Dependencias del sistema
RUN apt-get update && apt-get install -y \
    git unzip curl \
    libzip-dev libicu-dev libonig-dev \
    libxml2-dev libpng-dev libjpeg-dev libfreetype6-dev \
    libcurl4-openssl-dev pkg-config libssl-dev \
    --no-install-recommends \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

#  Extensiones built-in (sin opcache, ya viene integrado en PHP 8.5)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        zip \
        intl \
        bcmath \
        exif \
        gd \
        pcntl

#  Configuración de OPcache (ya está built-in, solo se configura)
RUN echo "opcache.enable=1\n\
opcache.memory_consumption=128\n\
opcache.max_accelerated_files=10000\n\
opcache.validate_timestamps=0" \
    > /usr/local/etc/php/conf.d/opcache.ini

#  Redis via PECL
RUN pecl install redis \
    && docker-php-ext-enable redis

#  PHP ini para producción
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

#  Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

#  Node 24 — para compilar los assets de Vite/Tailwind/Livewire
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs --no-install-recommends \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

#  Xdebug SOLO para desarrollo local: docker-compose.dev.yml lo activa con
#  INSTALL_XDEBUG=true. En producción el argumento queda en false y no se instala.
ARG INSTALL_XDEBUG=false
RUN if [ "$INSTALL_XDEBUG" = "true" ]; then pecl install xdebug && docker-php-ext-enable xdebug; fi

#  Usuario no-root
RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

WORKDIR /var/www/html/orthoshoefix
USER www-data
