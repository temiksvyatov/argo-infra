#!/bin/bash
set -e

echo "========================================"
echo "Установка PostgreSQL с mTLS"
echo "========================================"
echo ""

# Проверка наличия необходимых команд
command -v docker >/dev/null 2>&1 || { echo "Ошибка: docker не установлен" >&2; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "Ошибка: docker compose не установлен" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "Ошибка: openssl не установлен" >&2; exit 1; }

echo "Шаг 1: Генерация сертификатов..."
chmod +x generate-certs.sh
./generate-certs.sh

echo ""
echo "Шаг 2: Остановка существующих контейнеров..."
docker compose down -v 2>/dev/null || true

echo ""
echo "Шаг 3: Сборка и запуск PostgreSQL..."
docker compose build
docker compose up -d

echo ""
echo "Шаг 4: Ожидание готовности PostgreSQL..."
for i in {1..60}; do
    if docker compose exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
        echo "PostgreSQL готов!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Ошибка: PostgreSQL не готов после 60 секунд ожидания"
        docker compose logs
        exit 1
    fi
    echo -n "."
    sleep 1
done

echo ""
echo ""
echo "========================================"
echo "Установка завершена успешно!"
echo "========================================"
echo ""
echo "Информация о подключении:"
echo "  Host: localhost"
echo "  Port: 5432"
echo ""
echo "Базы данных и пользователи:"
echo "  - apidoc (пользователь: apidoc, сертификаты: ./certs/client-apidoc/)"
echo "  - apiman (пользователь: apiman, сертификаты: ./certs/client-apiman/)"
echo "  - kpi (пользователь: kpi, сертификаты: ./certs/client-kpi/)"
echo ""
echo "Для тестирования подключений выполните:"
echo "  ./test-connections.sh"
echo ""
echo "Для просмотра логов:"
echo "  docker compose logs -f"
echo ""
