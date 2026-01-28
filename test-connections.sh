#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
CERTS_DIR="./certs"

echo "========================================"
echo "Тестирование mTLS подключений к PostgreSQL"
echo "========================================"
echo ""

# Функция для тестирования подключения
test_connection() {
    local user=$1
    local database=$2
    local cert_dir="$CERTS_DIR/client-$user"
    
    echo -n "Тестирование: $user -> $database ... "
    
    if PGSSLMODE=verify-full \
       PGSSLROOTCERT="$cert_dir/ca-cert.pem" \
       PGSSLCERT="$cert_dir/$user-cert.pem" \
       PGSSLKEY="$cert_dir/$user-key.pem" \
       psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$user" -d "$database" -c "SELECT 'Connection successful' as status, current_database(), current_user;" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ УСПЕШНО${NC}"
        return 0
    else
        echo -e "${RED}✗ ОШИБКА${NC}"
        return 1
    fi
}

# Функция для проверки доступа к данным
test_data_access() {
    local user=$1
    local database=$2
    local cert_dir="$CERTS_DIR/client-$user"
    
    echo -n "  Проверка доступа к данным в $database ... "
    
    result=$(PGSSLMODE=verify-full \
             PGSSLROOTCERT="$cert_dir/ca-cert.pem" \
             PGSSLCERT="$cert_dir/$user-cert.pem" \
             PGSSLKEY="$cert_dir/$user-key.pem" \
             psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$user" -d "$database" -t -c "SELECT data FROM test_table LIMIT 1;" 2>/dev/null | xargs)
    
    if [ -n "$result" ]; then
        echo -e "${GREEN}✓ Данные получены: $result${NC}"
        return 0
    else
        echo -e "${RED}✗ Нет доступа к данным${NC}"
        return 1
    fi
}

# Функция для проверки отсутствия доступа
test_no_access() {
    local user=$1
    local database=$2
    local cert_dir="$CERTS_DIR/client-$user"
    
    echo -n "  Проверка отсутствия доступа: $user -> $database ... "
    
    if PGSSLMODE=verify-full \
       PGSSLROOTCERT="$cert_dir/ca-cert.pem" \
       PGSSLCERT="$cert_dir/$user-cert.pem" \
       PGSSLKEY="$cert_dir/$user-key.pem" \
       psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$user" -d "$database" -c "SELECT 1;" > /dev/null 2>&1; then
        echo -e "${RED}✗ ОШИБКА: доступ разрешен (должен быть запрещен)${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Доступ корректно запрещен${NC}"
        return 0
    fi
}

echo "Ожидание готовности PostgreSQL..."
for i in {1..30}; do
    if pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" > /dev/null 2>&1; then
        echo -e "${GREEN}PostgreSQL готов к подключениям${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}PostgreSQL не готов после 30 секунд ожидания${NC}"
        exit 1
    fi
    sleep 1
done

echo ""
echo "--- Тест 1: Проверка подключений пользователей к своим БД ---"
echo ""

USERS=("apidoc" "apiman" "kpi")
SUCCESS=0
FAILED=0

for user in "${USERS[@]}"; do
    if test_connection "$user" "$user"; then
        test_data_access "$user" "$user"
        ((SUCCESS++))
    else
        ((FAILED++))
    fi
    echo ""
done

echo ""
echo "--- Тест 2: Проверка отсутствия доступа к чужим БД ---"
echo ""

# apidoc не должен иметь доступ к apiman и kpi
test_no_access "apidoc" "apiman"
test_no_access "apidoc" "kpi"
echo ""

# apiman не должен иметь доступ к apidoc и kpi
test_no_access "apiman" "apidoc"
test_no_access "apiman" "kpi"
echo ""

# kpi не должен иметь доступ к apidoc и apiman
test_no_access "kpi" "apidoc"
test_no_access "kpi" "apiman"
echo ""

echo "========================================"
echo "Результаты тестирования:"
echo "  Успешных подключений: $SUCCESS/3"
echo "  Неудачных подключений: $FAILED/3"
echo "========================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}Все тесты пройдены успешно!${NC}"
    exit 0
else
    echo -e "${RED}Некоторые тесты завершились с ошибками${NC}"
    exit 1
fi
