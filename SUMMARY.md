# PostgreSQL 18 с mTLS - Итоговая документация

## Что было создано

### 1. Docker инфраструктура

**Файлы:**
- `docker-compose.yml` - Docker Compose конфигурация
- `Dockerfile` - Образ PostgreSQL 18 с SSL
- `docker-entrypoint-wrapper.sh` - Wrapper для корректной настройки прав на сертификаты
- `postgresql.conf` - Конфигурация PostgreSQL с SSL
- `pg_hba.conf` - Правила аутентификации (только mTLS)
- `init-db.sql` - SQL скрипт инициализации БД и пользователей

**Что работает:**
- PostgreSQL 18 в Docker
- 3 базы данных: apidoc, apiman, kpi
- 3 пользователя с доступом только к своим БД
- mTLS аутентификация (cert-based)
- Изоляция пользователей

### 2. Генерация сертификатов

**Файлы:**
- `generate-certs.sh` - Генерация всех сертификатов

**Что создается:**
- CA сертификат
- Серверный сертификат с SAN для различных hostname
- Клиентские сертификаты для каждого пользователя

**Важно:** 
- Серверный сертификат включает: `srv8-objkrugess.mfactory.nxcloud.nexign.com`, `localhost`, `*.mfactory.nxcloud.nexign.com`
- Клиентские сертификаты с CN=username для pg_hba.conf

### 3. Скрипты автоматизации

**Docker:**
- `setup.sh` - Полная установка (сертификаты + сборка + запуск)
- `cleanup.sh` - Очистка всего
- `test-connections.sh` - Тестирование локальных mTLS подключений

**Kubernetes:**
- `create-k8s-secrets.sh` - Создание secrets с сертификатами
- `deploy-k8s.sh` - Полное развертывание в K8s
- `test-k8s-connection.sh` - Тестирование подключений из K8s

**Примеры:**
- `connection-examples.sh` - Примеры подключения для разных языков

### 4. Kubernetes + Istio манифесты

**Файлы в k8s/:**
- `00-namespace.yaml` - Namespace с Istio injection
- `01-secrets.yaml` - Template для secrets (создаются скриптом)
- `02-serviceentry.yaml` - Регистрация внешнего PostgreSQL
- `03-destinationrule.yaml` - Настройки mTLS для каждого пользователя
- `04-test-pod-apidoc.yaml` - Тестовый pod с явными сертификатами
- `05-test-pod-simple.yaml` - Тестовый pod (Istio управляет mTLS)

**Документация:**
- `k8s/README.md` - Руководство по использованию в K8s
- `k8s/ISTIO-MTLS-GUIDE.md` - Подробное руководство по Istio mTLS

## Архитектура решения

### Локальное тестирование (Docker)

```
┌─────────────────────┐
│   Docker Host       │
│                     │
│  ┌──────────────┐   │
│  │ PostgreSQL   │   │
│  │ Container    │   │
│  │              │   │
│  │ - mTLS only  │   │
│  │ - Port 5432  │   │
│  └──────────────┘   │
└─────────────────────┘
         ▲
         │ mTLS
         │
    ┌────┴────┐
    │ psql    │
    │ client  │
    └─────────┘
```

### Production (K8s + Istio)

```
┌────────────────────────────────────┐
│  Kubernetes Cluster с Istio        │
│                                    │
│  ┌─────────────────────────────┐  │
│  │  Application Pod            │  │
│  │                             │  │
│  │  ┌───────────────────────┐  │  │
│  │  │ App Container         │  │  │
│  │  │ (подключение без SSL) │  │  │
│  │  └──────────┬────────────┘  │  │
│  │             │                │  │
│  │  ┌──────────▼────────────┐  │  │
│  │  │ Istio Sidecar (Envoy) │  │  │
│  │  │ - Перехватывает TCP   │  │  │
│  │  │ - Добавляет mTLS      │  │  │
│  │  │ - Использует secrets  │  │  │
│  │  └──────────┬────────────┘  │  │
│  └─────────────┼───────────────┘  │
│                │                   │
└────────────────┼───────────────────┘
                 │
                 │ mTLS через Internet
                 │
         ┌───────▼──────────────────┐
         │  External Host           │
         │  srv8-objkrugess...      │
         │                          │
         │  ┌────────────────────┐  │
         │  │ PostgreSQL 18      │  │
         │  │ - mTLS only        │  │
         │  │ - Port 5432        │  │
         │  └────────────────────┘  │
         └──────────────────────────┘
```

## Ключевые особенности

### 1. Безопасность

✅ **Только mTLS аутентификация** - никаких паролей
✅ **Изоляция пользователей** - каждый видит только свою БД
✅ **Проверка сертификатов** - verify-full режим
✅ **Централизованное управление сертификатами** через Kubernetes secrets

### 2. PostgreSQL 18 специфика

✅ **Правильная структура директорий** - `/var/lib/postgresql/` вместо `/var/lib/postgresql/data/`
✅ **Автоматическая инициализация** - скрипты в docker-entrypoint-initdb.d
✅ **Права на сертификаты** - wrapper для установки правильных прав

### 3. Istio интеграция

✅ **Прозрачный mTLS** - приложение не знает о SSL
✅ **ServiceEntry** - регистрация внешнего сервиса
✅ **DestinationRule** - политики mTLS
✅ **Автоматический sidecar injection** - через namespace label

## Быстрый старт

### Шаг 1: Локальное тестирование

```bash
# Генерация сертификатов
./generate-certs.sh

# Запуск PostgreSQL в Docker
./setup.sh

# Тестирование подключений
./test-connections.sh
```

**Ожидаемый результат:**
```
========================================
Результаты тестирования:
  Успешных подключений: 3/3
  Неудачных подключений: 0/3
========================================
✓ Все тесты пройдены успешно!
```

### Шаг 2: Развертывание в Kubernetes

```bash
# Развертывание всего
./deploy-k8s.sh

# Тестирование из K8s
./test-k8s-connection.sh
```

## Структура проекта

```
argo-infra/
├── README.md                      # Основная документация
├── SUMMARY.md                     # Этот файл
├── .env.example                   # Пример переменных окружения
├── .gitignore                     # Git ignore
│
├── Docker файлы
├── docker-compose.yml             # Docker Compose
├── Dockerfile                     # Образ PostgreSQL
├── docker-entrypoint-wrapper.sh   # Wrapper для прав на сертификаты
├── postgresql.conf                # Конфигурация PostgreSQL
├── pg_hba.conf                    # Правила аутентификации
├── init-db.sql                    # Инициализация БД
│
├── Скрипты
├── generate-certs.sh              # Генерация сертификатов
├── setup.sh                       # Установка Docker версии
├── cleanup.sh                     # Очистка
├── test-connections.sh            # Тестирование локально
├── connection-examples.sh         # Примеры подключений
│
├── Kubernetes скрипты
├── create-k8s-secrets.sh          # Создание secrets
├── deploy-k8s.sh                  # Развертывание в K8s
├── test-k8s-connection.sh         # Тестирование K8s
│
├── Kubernetes манифесты
├── k8s/
│   ├── README.md                  # Документация K8s
│   ├── ISTIO-MTLS-GUIDE.md        # Руководство по Istio
│   ├── 00-namespace.yaml          # Namespace
│   ├── 01-secrets.yaml            # Secrets template
│   ├── 02-serviceentry.yaml       # ServiceEntry
│   ├── 03-destinationrule.yaml    # DestinationRule
│   ├── 04-test-pod-apidoc.yaml    # Тестовый pod
│   └── 05-test-pod-simple.yaml    # Простой тестовый pod
│
├── Утилиты
├── kubectl                        # kubectl binary
└── kubeconfig                     # kubeconfig файл
```

## Используемые технологии

- **PostgreSQL 18** - СУБД
- **Docker & Docker Compose** - Контейнеризация
- **OpenSSL** - Генерация сертификатов
- **Kubernetes** - Оркестрация
- **Istio** - Service Mesh
- **Bash** - Автоматизация

## Дальнейшие шаги

### Production готовность

1. **Автоматическая ротация сертификатов**
   - Интеграция с cert-manager
   - Или использование Vault

2. **Мониторинг**
   - Prometheus метрики
   - Grafana дашборды
   - Алерты на ошибки TLS

3. **Backup & Recovery**
   - Автоматические бэкапы PostgreSQL
   - Disaster recovery план

4. **High Availability**
   - PostgreSQL репликация
   - Failover механизм

5. **Разделение по namespace**
   - Отдельный namespace для каждого пользователя
   - Network policies

### Безопасность

1. **Secrets management**
   - Sealed Secrets
   - External Secrets Operator
   - Vault integration

2. **Аудит**
   - Логирование всех подключений
   - Анализ доступа

3. **Обновления**
   - Регулярное обновление сертификатов
   - Патчи безопасности PostgreSQL

## Контакты и поддержка

Для вопросов и issues см. документацию:
- `README.md` - Основное руководство
- `k8s/README.md` - Kubernetes специфика
- `k8s/ISTIO-MTLS-GUIDE.md` - Детали Istio mTLS
