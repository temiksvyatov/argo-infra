#!/bin/bash

echo "========================================"
echo "Тестирование подключений из K8s к PostgreSQL"
echo "========================================"
echo ""

# Проверка kubectl
if [ ! -f "./kubectl" ]; then
    echo "ОШИБКА: kubectl не найден"
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Проверка статуса подов..."
./kubectl get pods -n postgres-client

echo ""
echo "--- Тест: Подключение через Istio mTLS ---"
echo ""

if ./kubectl get pod postgres-test-simple -n postgres-client &>/dev/null; then
    echo "Тестирование подключения..."
    
    if ./kubectl exec -n postgres-client postgres-test-simple -- \
        psql -h srv8-objkrugess.mfactory.nxcloud.nexign.com -p 5432 -U apidoc -d apidoc \
        -c "SELECT 'Connection via Istio successful' as status, current_user, current_database();" 2>/dev/null; then
        echo -e "${GREEN}✓ Подключение через Istio успешно${NC}"
    else
        echo -e "${RED}✗ Ошибка подключения через Istio${NC}"
    fi
    
    echo ""
    echo "Тест доступа к данным..."
    result=$(./kubectl exec -n postgres-client postgres-test-simple -- \
        psql -h srv8-objkrugess.mfactory.nxcloud.nexign.com -p 5432 -U apidoc -d apidoc \
        -t -c "SELECT data FROM test_table LIMIT 1;" 2>/dev/null | xargs)
    
    if [ -n "$result" ]; then
        echo -e "${GREEN}✓ Доступ к данным успешен: $result${NC}"
    else
        echo -e "${RED}✗ Нет доступа к данным${NC}"
    fi
else
    echo -e "${YELLOW}Pod postgres-test-simple не найден${NC}"
fi

echo ""
echo "--- Логи Istio sidecar ---"
echo ""
if ./kubectl get pod postgres-test-simple -n postgres-client &>/dev/null; then
    echo "Последние 20 строк логов istio-proxy:"
    ./kubectl logs -n postgres-client postgres-test-simple -c istio-proxy --tail=20 2>/dev/null || echo "Логи недоступны"
fi

echo ""
echo "========================================"
echo "Тестирование завершено"
echo "========================================"
