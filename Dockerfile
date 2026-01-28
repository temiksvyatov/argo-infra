FROM postgres:18

# Установка необходимых пакетов
RUN apt-get update && apt-get install -y \
    openssl \
    postgresql-contrib \
    && rm -rf /var/lib/apt/lists/*

# Создание директорий для сертификатов
RUN mkdir -p /etc/postgresql-certs /var/lib/postgresql/ssl-certs && \
    chown -R postgres:postgres /etc/postgresql-certs /var/lib/postgresql/ssl-certs

# Копирование конфигурационных файлов
COPY pg_hba.conf /etc/postgresql/pg_hba.conf
COPY postgresql.conf /etc/postgresql/postgresql.conf

# Создание скрипта для применения конфигурации
RUN echo '#!/bin/bash\n\
set -e\n\
echo "==> Применение конфигурации PostgreSQL для mTLS"\n\
\n\
# Используем переменную PGDATA, которая устанавливается docker-entrypoint\n\
if [ -z "$PGDATA" ]; then\n\
  PGVERSION=$(pg_config --version | sed "s/[^0-9]*//g" | cut -c1-2)\n\
  # Ищем директорию данных в различных возможных местах\n\
  for dir in "/var/lib/postgresql/${PGVERSION}/data" "/var/lib/postgresql/data" "$PGDATA"; do\n\
    if [ -d "$dir" ] && [ -f "$dir/PG_VERSION" ]; then\n\
      DATA_DIR="$dir"\n\
      break\n\
    fi\n\
  done\n\
else\n\
  DATA_DIR="$PGDATA"\n\
fi\n\
\n\
echo "    Директория данных: ${DATA_DIR}"\n\
\n\
if [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR" ]; then\n\
  echo "    Копирование pg_hba.conf..."\n\
  cp /etc/postgresql/pg_hba.conf "$DATA_DIR/pg_hba.conf"\n\
  chown postgres:postgres "$DATA_DIR/pg_hba.conf"\n\
  chmod 600 "$DATA_DIR/pg_hba.conf"\n\
  \n\
  echo "    Добавление настроек из postgresql.conf..."\n\
  cat /etc/postgresql/postgresql.conf >> "$DATA_DIR/postgresql.conf"\n\
  chown postgres:postgres "$DATA_DIR/postgresql.conf"\n\
  chmod 600 "$DATA_DIR/postgresql.conf"\n\
  \n\
  echo "    Конфигурационные файлы успешно применены"\n\
else\n\
  echo "    ВНИМАНИЕ: Директория данных не найдена или не инициализирована"\n\
  echo "    Проверьте: ls -la /var/lib/postgresql/"\n\
  ls -la /var/lib/postgresql/ || true\n\
  exit 1\n\
fi\n\
' > /docker-entrypoint-initdb.d/00-copy-config.sh && \
    chmod +x /docker-entrypoint-initdb.d/00-copy-config.sh

# Копирование SQL скрипта инициализации
COPY init-db.sql /docker-entrypoint-initdb.d/01-init.sql

# Копирование wrapper для entrypoint
COPY docker-entrypoint-wrapper.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh

# Установка переменных окружения
ENV POSTGRES_HOST_AUTH_METHOD=trust
ENV POSTGRES_INITDB_ARGS="--auth-host=md5 --auth-local=trust"

# Использование wrapper entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wrapper.sh"]
CMD ["postgres"]

EXPOSE 5432
