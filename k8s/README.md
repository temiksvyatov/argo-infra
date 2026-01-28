# PostgreSQL mTLS с Istio в Kubernetes

Конфигурация для подключения приложений из Kubernetes кластера с Istio к внешнему PostgreSQL с mTLS аутентификацией.

## Архитектура

```
┌─────────────────────────────────────┐
│   Kubernetes Cluster с Istio        │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Application Pod             │  │
│  │  ┌────────────────────────┐  │  │
│  │  │  App Container         │  │  │
│  │  │  (без SSL)             │  │  │
│  │  └─────────┬──────────────┘  │  │
│  │            │                  │  │
│  │  ┌─────────▼──────────────┐  │  │
│  │  │  Istio Sidecar         │  │  │
│  │  │  (добавляет mTLS)      │  │  │
│  │  └─────────┬──────────────┘  │  │
│  └────────────┼──────────────────┘  │
│               │                     │
└───────────────┼─────────────────────┘
                │ mTLS
                ▼
        ┌───────────────┐
        │  PostgreSQL   │
        │  на хосте     │
        │  (mTLS only)  │
        └───────────────┘
```

## Компоненты

### 1. Namespace (00-namespace.yaml)
- Namespace `postgres-client` с включенной Istio injection

### 2. Secrets (создаются скриптом)
- `postgres-apidoc-certs` - сертификаты для пользователя apidoc
- `postgres-apiman-certs` - сертификаты для пользователя apiman  
- `postgres-kpi-certs` - сертификаты для пользователя kpi

### 3. ServiceEntry (02-serviceentry.yaml)
- Регистрирует внешний PostgreSQL сервер в Istio service mesh
- Host: `srv8-objkrugess.mfactory.nxcloud.nexign.com`
- Port: 5432

### 4. DestinationRule (03-destinationrule.yaml)
- Настраивает mTLS для каждого пользователя
- Указывает пути к сертификатам
- Режим: MUTUAL (двусторонний TLS)

### 5. Test Pods
- `postgres-test-apidoc` - с явными сертификатами
- `postgres-test-simple` - Istio управляет mTLS автоматически

## Быстрый старт

### 1. Генерация сертификатов (если не сделано)
```bash
cd ..
./generate-certs.sh
```

### 2. Развертывание в K8s
```bash
cd ..
./deploy-k8s.sh
```

Или пошагово:
```bash
# Создание secrets
./create-k8s-secrets.sh

# Применение Istio конфигурации
./kubectl apply -f k8s/02-serviceentry.yaml
./kubectl apply -f k8s/03-destinationrule.yaml

# Запуск тестовых подов
./kubectl apply -f k8s/04-test-pod-apidoc.yaml
./kubectl apply -f k8s/05-test-pod-simple.yaml
```

### 3. Тестирование
```bash
./test-k8s-connection.sh
```

Или вручную:
```bash
# Проверка статуса
./kubectl get pods -n postgres-client

# Тест подключения
./kubectl exec -n postgres-client postgres-test-apidoc -- \
  env PGSSLMODE=verify-full \
      PGSSLROOTCERT=/etc/certs/apidoc/ca.crt \
      PGSSLCERT=/etc/certs/apidoc/tls.crt \
      PGSSLKEY=/etc/certs/apidoc/tls.key \
  psql -h srv8-objkrugess.mfactory.nxcloud.nexign.com \
       -p 5432 -U apidoc -d apidoc \
       -c "SELECT current_user, current_database();"

# Просмотр логов Istio sidecar
./kubectl logs -n postgres-client postgres-test-apidoc -c istio-proxy
```

## Использование в приложении

### Вариант 1: Istio управляет mTLS (рекомендуется)

Приложение подключается БЕЗ SSL, Istio sidecar добавляет mTLS автоматически:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: postgres-client
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: DB_HOST
      value: "srv8-objkrugess.mfactory.nxcloud.nexign.com"
    - name: DB_PORT
      value: "5432"
    - name: DB_USER
      value: "apidoc"
    - name: DB_NAME
      value: "apidoc"
    - name: DB_SSLMODE
      value: "disable"  # Istio добавит mTLS
```

### Вариант 2: Приложение управляет сертификатами

Если приложение должно напрямую использовать сертификаты:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: postgres-client
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: DB_HOST
      value: "srv8-objkrugess.mfactory.nxcloud.nexign.com"
    - name: PGSSLMODE
      value: "verify-full"
    - name: PGSSLROOTCERT
      value: "/etc/postgres-certs/ca.crt"
    - name: PGSSLCERT
      value: "/etc/postgres-certs/tls.crt"
    - name: PGSSLKEY
      value: "/etc/postgres-certs/tls.key"
    volumeMounts:
    - name: postgres-certs
      mountPath: /etc/postgres-certs
      readOnly: true
  volumes:
  - name: postgres-certs
    secret:
      secretName: postgres-apidoc-certs
```

## Отладка

### Проверка Istio конфигурации
```bash
# ServiceEntry
./kubectl get serviceentry -n postgres-client

# DestinationRule
./kubectl get destinationrule -n postgres-client

# Описание DestinationRule
./kubectl describe destinationrule postgres-apidoc-mtls -n postgres-client
```

### Проверка сертификатов в секретах
```bash
./kubectl get secret postgres-apidoc-certs -n postgres-client -o yaml
```

### Логи Istio sidecar
```bash
./kubectl logs -n postgres-client postgres-test-apidoc -c istio-proxy
```

### Проверка Istio proxy конфигурации
```bash
./kubectl exec -n postgres-client postgres-test-apidoc -c istio-proxy -- \
  pilot-agent request GET config_dump
```

## Очистка

```bash
# Удаление всех ресурсов
./kubectl delete namespace postgres-client

# Или по отдельности
./kubectl delete -f k8s/
```

## Troubleshooting

### Ошибка: connection refused
- Проверьте, что PostgreSQL доступен с хоста: `telnet srv8-objkrugess.mfactory.nxcloud.nexign.com 5432`
- Проверьте ServiceEntry: `./kubectl get serviceentry -n postgres-client`

### Ошибка: certificate verify failed
- Проверьте, что сертификаты правильно загружены в секреты
- Проверьте CN в серверном сертификате PostgreSQL
- Проверьте DestinationRule настройки mTLS

### Pod в состоянии Pending
- Проверьте наличие nodes: `./kubectl get nodes`
- Проверьте события: `./kubectl get events -n postgres-client`

### Istio sidecar не инжектится
- Проверьте label namespace: `./kubectl get namespace postgres-client --show-labels`
- Должен быть `istio-injection=enabled`
