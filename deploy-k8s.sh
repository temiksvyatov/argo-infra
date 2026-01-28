#!/bin/bash
set -e

echo "========================================"
echo "Развертывание PostgreSQL mTLS клиентов в K8s"
echo "========================================"
echo ""

# Проверка kubectl
if [ ! -f "./kubectl" ]; then
    echo "ОШИБКА: kubectl не найден в текущей директории"
    exit 1
fi

# Проверка сертификатов
if [ ! -d "certs" ]; then
    echo "Сертификаты не найдены. Генерирую..."
    ./generate-certs.sh
fi

echo "Шаг 1: Создание namespace и secrets..."
./create-k8s-secrets.sh

echo ""
echo "Шаг 2: Применение Istio конфигурации..."
./kubectl apply -f k8s/02-serviceentry.yaml
./kubectl apply -f k8s/03-destinationrule.yaml

echo ""
echo "Шаг 3: Запуск тестового пода..."
./kubectl apply -f k8s/05-test-pod-simple.yaml

echo ""
echo "Ожидание запуска пода..."
./kubectl wait --for=condition=Ready pod/postgres-test-simple -n postgres-client --timeout=60s || true

echo ""
echo "========================================"
echo "Развертывание завершено!"
echo "========================================"
echo ""
echo "Проверка статуса:"
echo "  ./kubectl get pods -n postgres-client"
echo ""
echo "Тестирование подключения:"
echo "  ./kubectl exec -n postgres-client postgres-test-simple -- psql -U apidoc -d apidoc -c 'SELECT current_user, current_database();'"
echo ""
echo "Просмотр логов Istio sidecar:"
echo "  ./kubectl logs -n postgres-client postgres-test-simple -c istio-proxy"
