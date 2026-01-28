# Руководство по Security Context в Kubernetes

## Что такое Security Context

Security Context определяет привилегии и настройки контроля доступа для Pod или контейнера.

## Уровни Security Context

### 1. Pod Security Context

Применяется ко всем контейнерам в Pod:

```yaml
spec:
  securityContext:
    runAsNonRoot: true      # Запрет запуска от root
    runAsUser: 1000         # UID пользователя
    runAsGroup: 1000        # GID группы
    fsGroup: 1000           # GID для volumes
    seccompProfile:         # Профиль seccomp
      type: RuntimeDefault
```

### 2. Container Security Context

Применяется к конкретному контейнеру (переопределяет Pod-level):

```yaml
containers:
- name: app
  securityContext:
    allowPrivilegeEscalation: false  # Запрет повышения привилегий
    runAsNonRoot: true
    runAsUser: 1000
    capabilities:
      drop:
        - ALL                        # Сброс всех capabilities
    readOnlyRootFilesystem: true    # Read-only корневая ФС
```

## Основные параметры

### runAsNonRoot

```yaml
runAsNonRoot: true
```

**Что делает:** Запрещает запуск контейнера от root (UID 0)

**Почему важно:** 
- Ограничивает возможности атакующего при компрометации контейнера
- Предотвращает escape из контейнера через уязвимости ядра

**Best practice:** Всегда `true` для production

### runAsUser / runAsGroup

```yaml
runAsUser: 1000
runAsGroup: 1000
```

**Что делает:** Задает UID/GID для процессов в контейнере

**Рекомендации:**
- Используйте непривилегированные UID (> 1000)
- Убедитесь, что образ поддерживает этот UID
- Для PostgreSQL клиента: `999` (postgres user в образе)

### fsGroup

```yaml
fsGroup: 1000
```

**Что делает:** 
- Устанавливает GID для всех volumes
- Файлы в volumes будут принадлежать этой группе

**Когда использовать:**
- При монтировании secrets/configmaps
- Для shared volumes между контейнерами

### allowPrivilegeEscalation

```yaml
allowPrivilegeEscalation: false
```

**Что делает:** Запрещает процессу получать больше привилегий чем родительский процесс

**Best practice:** Всегда `false` для production

### capabilities

```yaml
capabilities:
  drop:
    - ALL
  add:
    - NET_BIND_SERVICE  # Только если нужно
```

**Что делает:** Управляет Linux capabilities

**Рекомендации:**
- Всегда сбрасывайте `ALL`
- Добавляйте только необходимые capabilities
- Примеры нужных capabilities:
  - `NET_BIND_SERVICE` - для портов < 1024
  - `CHOWN` - для изменения владельца файлов

### readOnlyRootFilesystem

```yaml
readOnlyRootFilesystem: true
```

**Что делает:** Делает корневую ФС контейнера read-only

**Преимущества:**
- Защита от модификации файлов
- Предотвращение записи вредоносного кода

**Проблемы:**
- Приложению нужны writable директории (`/tmp`, кеши)
- Решение: монтировать `emptyDir` для writable путей

```yaml
volumeMounts:
- name: tmp
  mountPath: /tmp
- name: cache
  mountPath: /app/cache

volumes:
- name: tmp
  emptyDir: {}
- name: cache
  emptyDir: {}
```

### seccompProfile

```yaml
seccompProfile:
  type: RuntimeDefault
```

**Что делает:** Применяет профиль seccomp для ограничения syscalls

**Типы:**
- `RuntimeDefault` - профиль по умолчанию (рекомендуется)
- `Unconfined` - без ограничений (не рекомендуется)
- `Localhost` - кастомный профиль

**Best practice:** Используйте `RuntimeDefault`

## Примеры для разных сценариев

### Максимальная безопасность (Restricted)

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
          - ALL
      readOnlyRootFilesystem: true
```

### Для PostgreSQL клиента

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 999        # postgres user
    runAsGroup: 999
    fsGroup: 999
    seccompProfile:
      type: RuntimeDefault
  
  containers:
  - name: postgres-client
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 999
      capabilities:
        drop:
          - ALL
      readOnlyRootFilesystem: false  # psql создает временные файлы
    
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: postgres-tmp
      mountPath: /var/lib/postgresql
  
  volumes:
  - name: tmp
    emptyDir: {}
  - name: postgres-tmp
    emptyDir: {}
```

### Для веб-приложения

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  
  containers:
  - name: webapp
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      capabilities:
        drop:
          - ALL
      readOnlyRootFilesystem: true
    
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /app/cache
    
  volumes:
  - name: tmp
    emptyDir:
      medium: Memory      # RAM disk для /tmp
      sizeLimit: 100Mi
  - name: cache
    emptyDir:
      sizeLimit: 500Mi
```

## Pod Security Standards (PSS)

Kubernetes определяет 3 уровня безопасности:

### Privileged
Без ограничений (не рекомендуется для production)

### Baseline
Минимальные ограничения:
- Запрет privileged контейнеров
- Запрет hostNetwork, hostPID, hostIPC
- Ограничения на capabilities

### Restricted (рекомендуется)
Максимальные ограничения:
- Все из Baseline
- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- Сброс всех capabilities
- Seccomp профиль
- Ограничения на volume types

## Применение Pod Security Standards

### Через namespace labels (Kubernetes 1.23+)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: postgres-client
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Режимы:
- `enforce` - блокировать не соответствующие поды
- `audit` - логировать нарушения
- `warn` - предупреждать при создании

## Проверка Security Context

### kubectl

```bash
# Проверка текущего security context
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 20 securityContext

# Проверка нарушений PSS
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

### Kube-bench

Проверка соответствия CIS Kubernetes Benchmark:

```bash
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench
```

### Polaris

Аудит конфигурации на best practices:

```bash
kubectl apply -f https://github.com/FairwindsOps/polaris/releases/latest/download/dashboard.yaml
kubectl port-forward -n polaris svc/polaris-dashboard 8080:80
```

## Распространенные проблемы

### Ошибка: container has runAsNonRoot and image will run as root

**Причина:** Образ настроен на запуск от root

**Решение:**
1. Пересоберите образ с непривилегированным пользователем
2. Или переопределите USER в Pod:
```yaml
securityContext:
  runAsUser: 1000
```

### Ошибка: failed to create containerd task: failed to create shim: OCI runtime create failed

**Причина:** Недостаточно прав или несовместимый seccomp профиль

**Решение:**
1. Проверьте UID существует в образе
2. Проверьте права на файлы
3. Попробуйте без seccomp (временно для отладки)

### Приложение не работает с readOnlyRootFilesystem: true

**Причина:** Приложение пытается писать в ФС

**Решение:**
1. Найдите какие директории нужны для записи
2. Смонтируйте emptyDir для этих директорий
3. Или настройте приложение на использование /tmp

```yaml
volumeMounts:
- name: app-data
  mountPath: /app/data
- name: tmp
  mountPath: /tmp

volumes:
- name: app-data
  emptyDir: {}
- name: tmp
  emptyDir: {}
```

## Best Practices

### ✅ DO

1. **Всегда используйте runAsNonRoot: true**
2. **Сбрасывайте все capabilities**
3. **Используйте readOnlyRootFilesystem где возможно**
4. **Применяйте seccomp профиль**
5. **Используйте непривилегированные UID (> 1000)**
6. **Тестируйте на Restricted PSS**

### ❌ DON'T

1. **Не запускайте контейнеры от root**
2. **Не используйте privileged: true**
3. **Не добавляйте capabilities без необходимости**
4. **Не отключайте seccomp**
5. **Не используйте allowPrivilegeEscalation: true**

## Мигрирование существующих приложений

### Шаг 1: Аудит

```bash
# Проверка текущего состояния
kubectl get pods -n <namespace> -o json | \
  jq '.items[] | select(.spec.securityContext == null) | .metadata.name'
```

### Шаг 2: Добавление базового Security Context

Начните с минимальных ограничений:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
```

### Шаг 3: Постепенное ужесточение

1. Добавьте `allowPrivilegeEscalation: false`
2. Сбросьте capabilities
3. Добавьте seccomp профиль
4. Включите `readOnlyRootFilesystem: true`

### Шаг 4: Тестирование

Проверьте на каждом шаге:
- Приложение запускается
- Функционал работает
- Нет ошибок в логах

## Заключение

Security Context - критически важная часть безопасности Kubernetes. Следуйте принципу наименьших привилегий и используйте максимальные ограничения, которые позволяет ваше приложение.

Для наших PostgreSQL клиентов мы используем:
- ✅ runAsNonRoot: true
- ✅ allowPrivilegeEscalation: false
- ✅ Capabilities dropped
- ✅ Seccomp profile
- ⚠️  readOnlyRootFilesystem: false (из-за psql временных файлов)

Это обеспечивает хороший баланс между безопасностью и функциональностью.
