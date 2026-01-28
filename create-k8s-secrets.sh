#!/bin/bash
set -e

echo "========================================"
echo "Создание Kubernetes Secrets с сертификатами"
echo "========================================"
echo ""

# Проверка наличия kubectl
if ! command -v ./kubectl &> /dev/null; then
    echo "ОШИБКА: kubectl не найден в текущей директории"
    exit 1
fi

# Проверка наличия сертификатов
if [ ! -d "certs" ]; then
    echo "ОШИБКА: Директория certs не найдена. Выполните ./generate-certs.sh"
    exit 1
fi

USERS=("apidoc" "apiman" "kpi")

echo "Создание namespace postgres-client..."
./kubectl apply -f k8s/00-namespace.yaml

echo ""
echo "Создание secrets с сертификатами..."

for USER in "${USERS[@]}"; do
    echo ""
    echo "==> Создание secret для пользователя: $USER"
    
    CERT_DIR="certs/client-$USER"
    
    if [ ! -d "$CERT_DIR" ]; then
        echo "ОШИБКА: Директория $CERT_DIR не найдена"
        exit 1
    fi
    
    # Удаление существующего secret (если есть)
    ./kubectl delete secret "postgres-${USER}-certs" -n postgres-client 2>/dev/null || true
    
    # Создание нового secret
    ./kubectl create secret generic "postgres-${USER}-certs" \
        -n postgres-client \
        --from-file=ca.crt="$CERT_DIR/ca-cert.pem" \
        --from-file=tls.crt="$CERT_DIR/${USER}-cert.pem" \
        --from-file=tls.key="$CERT_DIR/${USER}-key.pem"
    
    echo "    Secret postgres-${USER}-certs создан"
done

echo ""
echo "========================================"
echo "Все secrets успешно созданы!"
echo "========================================"
echo ""
echo "Для применения остальных манифестов:"
echo "  ./kubectl apply -f k8s/02-serviceentry.yaml"
echo "  ./kubectl apply -f k8s/03-destinationrule.yaml"
echo "  ./kubectl apply -f k8s/04-test-pod-apidoc.yaml"
echo ""
echo "Или все сразу:"
echo "  ./kubectl apply -f k8s/"
