# PostgreSQL 18 с mTLS аутентификацией

Автоматизированная установка PostgreSQL 18 в Docker с mTLS аутентификацией для трех баз данных.

## Структура

- **3 базы данных**: apidoc, apiman, kpi
- **3 пользователя**: apidoc, apiman, kpi (каждый с доступом только к своей БД)
- **Аутентификация**: mTLS (сертификаты клиента)
- **PostgreSQL версия**: 18
- **Контейнеризация**: Docker + Docker Compose

## Быстрый старт

```bash
# Полная установка и запуск
./setup.sh

# Тестирование подключений
./test-connections.sh
```

## Ручная установка

```bash
# 1. Генерация сертификатов
./generate-certs.sh

# 2. Запуск PostgreSQL
docker-compose up -d

# 3. Проверка готовности
docker-compose logs -f
```

## Подключение к базам данных

### Пример для пользователя apidoc

```bash
PGSSLMODE=verify-full \
PGSSLROOTCERT=./certs/client-apidoc/ca-cert.pem \
PGSSLCERT=./certs/client-apidoc/apidoc-cert.pem \
PGSSLKEY=./certs/client-apidoc/apidoc-key.pem \
psql -h localhost -p 5432 -U apidoc -d apidoc
```

### Пример для пользователя apiman

```bash
PGSSLMODE=verify-full \
PGSSLROOTCERT=./certs/client-apiman/ca-cert.pem \
PGSSLCERT=./certs/client-apiman/apiman-cert.pem \
PGSSLKEY=./certs/client-apiman/apiman-key.pem \
psql -h localhost -p 5432 -U apiman -d apiman
```

### Пример для пользователя kpi

```bash
PGSSLMODE=verify-full \
PGSSLROOTCERT=./certs/client-kpi/ca-cert.pem \
PGSSLCERT=./certs/client-kpi/kpi-cert.pem \
PGSSLKEY=./certs/client-kpi/kpi-key.pem \
psql -h localhost -p 5432 -U kpi -d kpi
```

## Структура файлов

```
.
├── setup.sh                 # Полная автоматическая установка
├── cleanup.sh               # Очистка и удаление
├── generate-certs.sh        # Генерация сертификатов
├── test-connections.sh      # Тестирование подключений
├── docker-compose.yml       # Docker Compose конфигурация
├── Dockerfile               # Образ PostgreSQL
├── init-db.sql              # SQL скрипт инициализации
├── pg_hba.conf              # Конфигурация аутентификации
├── postgresql.conf          # Конфигурация PostgreSQL
└── certs/                   # Директория с сертификатами (создается автоматически)
    ├── ca-cert.pem          # CA сертификат
    ├── server-cert.pem      # Серверный сертификат
    ├── server-key.pem       # Серверный ключ
    ├── client-apidoc/       # Сертификаты пользователя apidoc
    ├── client-apiman/       # Сертификаты пользователя apiman
    └── client-kpi/          # Сертификаты пользователя kpi
```

## Использование в Kubernetes с Istio

Для подключения из Kubernetes кластера с Istio:

```bash
# 1. Генерация сертификатов (если не сделано)
./generate-certs.sh srv8-objkrugess.mfactory.nxcloud.nexign.com

# 2. Развертывание в K8s
./deploy-k8s.sh

# 3. Тестирование подключений
./test-k8s-connection.sh
```

Подробнее см. [k8s/README.md](k8s/README.md)

## Управление Docker

```bash
# Запуск
docker-compose up -d

# Остановка
docker-compose down

# Просмотр логов
docker-compose logs -f

# Полная очистка (удаление данных и сертификатов)
./cleanup.sh
```

## Безопасность

- Каждый пользователь имеет доступ только к своей базе данных
- Аутентификация только по клиентским сертификатам (mTLS)
- TLS версия не ниже 1.2
- Отключены все другие методы аутентификации

## Требования

- Docker
- Docker Compose
- OpenSSL
- PostgreSQL client (для тестирования)
