#!/bin/bash
set -e

echo "==> Настройка прав на SSL сертификаты"

# Проверка наличия сертификатов
if [ -d "/etc/postgresql-certs" ]; then
    echo "    Установка прав на сертификаты..."
    
    # Копирование сертификатов во временную директорию с правильными правами
    mkdir -p /var/lib/postgresql/ssl-certs
    
    if [ -f "/etc/postgresql-certs/server-key.pem" ]; then
        cp /etc/postgresql-certs/server-key.pem /var/lib/postgresql/ssl-certs/
        chown postgres:postgres /var/lib/postgresql/ssl-certs/server-key.pem
        chmod 600 /var/lib/postgresql/ssl-certs/server-key.pem
    fi
    
    if [ -f "/etc/postgresql-certs/server-cert.pem" ]; then
        cp /etc/postgresql-certs/server-cert.pem /var/lib/postgresql/ssl-certs/
        chown postgres:postgres /var/lib/postgresql/ssl-certs/server-cert.pem
        chmod 644 /var/lib/postgresql/ssl-certs/server-cert.pem
    fi
    
    if [ -f "/etc/postgresql-certs/ca-cert.pem" ]; then
        cp /etc/postgresql-certs/ca-cert.pem /var/lib/postgresql/ssl-certs/
        chown postgres:postgres /var/lib/postgresql/ssl-certs/ca-cert.pem
        chmod 644 /var/lib/postgresql/ssl-certs/ca-cert.pem
    fi
    
    echo "    Права на сертификаты установлены"
else
    echo "    ВНИМАНИЕ: Директория /etc/postgresql-certs не найдена"
fi

echo "    Запуск PostgreSQL..."
# Передаем управление оригинальному entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
