# Руководство по Istio mTLS для внешних сервисов

## Как работает Istio mTLS для внешнего PostgreSQL

### 1. Обычный flow (без Istio)

```
Application → PostgreSQL (с mTLS)
```

Приложение должно:
- Иметь клиентские сертификаты
- Настроить SSL соединение
- Управлять сертификатами и их обновлением

### 2. Flow с Istio

```
Application (без SSL) → Istio Sidecar (добавляет mTLS) → PostgreSQL
```

Преимущества:
- Приложение не знает о SSL/TLS
- Централизованное управление сертификатами
- Единая точка для мониторинга и логирования
- Автоматическая ротация сертификатов (если настроена)

## Компоненты Istio для внешнего mTLS

### ServiceEntry

Регистрирует внешний сервис в Istio service mesh:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: postgres-external
spec:
  hosts:
  - srv8-objkrugess.mfactory.nxcloud.nexign.com
  ports:
  - number: 5432
    name: postgres
    protocol: TCP
  location: MESH_EXTERNAL  # Сервис вне mesh
  resolution: DNS          # Разрешение через DNS
```

**Что делает:**
- Сообщает Istio о существовании внешнего сервиса
- Позволяет применять к нему политики Istio
- Включает мониторинг и трейсинг

### DestinationRule

Настраивает mTLS для подключения:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: postgres-apidoc-mtls
spec:
  host: srv8-objkrugess.mfactory.nxcloud.nexign.com
  trafficPolicy:
    tls:
      mode: MUTUAL                                    # Двусторонний TLS
      clientCertificate: /etc/certs/apidoc/tls.crt   # Клиентский сертификат
      privateKey: /etc/certs/apidoc/tls.key          # Приватный ключ
      caCertificates: /etc/certs/apidoc/ca.crt       # CA сертификат
      sni: srv8-objkrugess.mfactory.nxcloud.nexign.com # SNI
```

**Что делает:**
- Настраивает mTLS для исходящего трафика
- Указывает сертификаты для аутентификации
- Проверяет серверный сертификат

### Важные режимы TLS

- `DISABLE` - без TLS
- `SIMPLE` - односторонний TLS (только сервер аутентифицируется)
- `MUTUAL` - двусторонний TLS (клиент и сервер аутентифицируются)
- `ISTIO_MUTUAL` - mTLS между сервисами внутри mesh

## Как Istio sidecar обрабатывает трафик

### 1. Envoy перехватывает исходящий трафик

```
App → localhost:5432 → Envoy (через iptables) → Внешний PostgreSQL
```

Istio использует iptables для перехвата трафика:
- Исходящий трафик на порт 5432 перенаправляется на Envoy
- Envoy proxy (istio-proxy контейнер) обрабатывает соединение

### 2. Envoy применяет DestinationRule

- Находит подходящий DestinationRule для хоста
- Устанавливает TLS соединение с серверным сертификатом
- Отправляет клиентский сертификат для mTLS

### 3. Прозрачность для приложения

Приложение видит обычное TCP соединение:
```python
# Приложение делает простое подключение
conn = psycopg2.connect(
    host="srv8-objkrugess.mfactory.nxcloud.nexign.com",
    port=5432,
    user="apidoc",
    database="apidoc"
    # Без SSL параметров!
)
```

Istio sidecar автоматически:
- Добавляет mTLS
- Управляет сертификатами
- Логирует соединение

## Монтирование сертификатов в Istio sidecar

### Через Kubernetes Secret

```yaml
volumes:
- name: postgres-certs
  secret:
    secretName: postgres-apidoc-certs
```

### Автоматическое монтирование в sidecar

Istio автоматически монтирует секреты в sidecar, если указаны в DestinationRule:

```yaml
clientCertificate: /etc/certs/apidoc/tls.crt
privateKey: /etc/certs/apidoc/tls.key
caCertificates: /etc/certs/apidoc/ca.crt
```

**Важно:** Пути в DestinationRule должны соответствовать путям монтирования в Pod.

## Разные пользователи PostgreSQL

### Проблема

У нас 3 пользователя (apidoc, apiman, kpi), каждому нужны свои сертификаты.

### Решение 1: Разные DestinationRule

Создать отдельный DestinationRule для каждого пользователя (так сейчас):

```yaml
# postgres-apidoc-mtls
clientCertificate: /etc/certs/apidoc/tls.crt

# postgres-apiman-mtls
clientCertificate: /etc/certs/apiman/tls.crt

# postgres-kpi-mtls
clientCertificate: /etc/certs/kpi/tls.crt
```

**Недостаток:** Istio может применить любой из них (не детерминировано).

### Решение 2: Разные ServiceEntry с subset

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: postgres-external
spec:
  hosts:
  - postgres-apidoc.external
  - postgres-apiman.external
  - postgres-kpi.external
  endpoints:
  - address: srv8-objkrugess.mfactory.nxcloud.nexign.com
```

Приложение подключается к разным виртуальным хостам.

### Решение 3: Разные namespace

Каждый пользователь в своем namespace с собственным DestinationRule:

```
namespace apidoc-ns → postgres-apidoc-mtls
namespace apiman-ns → postgres-apiman-mtls
namespace kpi-ns → postgres-kpi-mtls
```

**Рекомендуется для production.**

## Мониторинг и отладка

### Просмотр логов Envoy

```bash
kubectl logs -n postgres-client <pod-name> -c istio-proxy
```

### Проверка активных соединений

```bash
kubectl exec -n postgres-client <pod-name> -c istio-proxy -- \
  curl localhost:15000/clusters | grep postgres
```

### Проверка конфигурации Envoy

```bash
kubectl exec -n postgres-client <pod-name> -c istio-proxy -- \
  curl localhost:15000/config_dump > envoy-config.json
```

Найдите секцию с вашим DestinationRule для проверки TLS настроек.

### Метрики Prometheus

Istio экспортирует метрики для исходящих соединений:
- `istio_tcp_connections_opened_total`
- `istio_tcp_connections_closed_total`
- `istio_tcp_sent_bytes_total`
- `istio_tcp_received_bytes_total`

## Best Practices

### 1. Используйте SNI (Server Name Indication)

```yaml
sni: srv8-objkrugess.mfactory.nxcloud.nexign.com
```

Это помогает серверу выбрать правильный сертификат.

### 2. Проверяйте серверный сертификат

```yaml
mode: MUTUAL  # Не SIMPLE
caCertificates: /etc/certs/apidoc/ca.crt
```

### 3. Используйте secrets для сертификатов

Не храните сертификаты в образах или ConfigMaps.

### 4. Настройте автоматическую ротацию

Используйте cert-manager или vault для автоматического обновления сертификатов.

### 5. Изолируйте пользователей

Разные namespace для разных пользователей PostgreSQL.

### 6. Мониторинг

Настройте алерты на ошибки TLS handshake в логах Envoy.

## Troubleshooting

### Ошибка: SSL connection has been closed unexpectedly

Проверьте:
1. Серверный сертификат включает правильный hostname
2. Клиентский сертификат подписан правильным CA
3. SNI соответствует CN в серверном сертификате

### Ошибка: no pg_hba.conf entry for host

PostgreSQL отклоняет подключение. Проверьте:
1. `pg_hba.conf` разрешает подключения с клиентским сертификатом
2. CN в клиентском сертификате совпадает с username

### Сертификат не найден в sidecar

Проверьте:
1. Secret существует: `kubectl get secret -n postgres-client`
2. Volume монтирован в Pod (не только в sidecar)
3. Пути в DestinationRule совпадают с путями монтирования

### DestinationRule не применяется

Проверьте:
1. Host в DestinationRule совпадает с Host в ServiceEntry
2. Namespace DestinationRule (должен быть тот же, что и Pod, или root namespace)
3. Логи istiod: `kubectl logs -n istio-system <istiod-pod>`
