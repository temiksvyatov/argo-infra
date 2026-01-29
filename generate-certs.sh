#!/bin/bash
set -e

# Директория для сертификатов
CERTS_DIR="./certs"
mkdir -p "$CERTS_DIR"

echo "==> Генерация сертификатов для PostgreSQL с mTLS"

# Генерация CA (Certificate Authority)
echo "==> Создание CA сертификата..."
openssl req -new -x509 -days 3650 -nodes \
    -keyout "$CERTS_DIR/ca-key.pem" \
    -out "$CERTS_DIR/ca-cert.pem" \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=Organization/OU=IT/CN=PostgreSQL-CA"

# Генерация серверного сертификата с SAN
echo "==> Создание серверного сертификата..."

# Дополнительный hostname (можно передать как параметр или использовать по умолчанию)
CUSTOM_HOSTNAME="${1:-srv8-objkrugess.mfactory.nxcloud.nexign.com}"

echo "    Добавление hostname в сертификат: $CUSTOM_HOSTNAME"

# Создание файла конфигурации для SAN
cat > "$CERTS_DIR/server-san.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = RU
ST = Moscow
L = Moscow
O = Organization
OU = IT
CN = $CUSTOM_HOSTNAME

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CUSTOM_HOSTNAME
DNS.2 = localhost
DNS.3 = postgres-server
DNS.4 = postgres-mtls
DNS.5 = postgres
DNS.6 = *.mfactory.nxcloud.nexign.com
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Генерация приватного ключа и запроса сертификата с SAN
openssl req -new -nodes \
    -keyout "$CERTS_DIR/server-key.pem" \
    -out "$CERTS_DIR/server-req.pem" \
    -config "$CERTS_DIR/server-san.cnf"

# Подписание серверного сертификата CA с расширениями
openssl x509 -req -days 3650 \
    -in "$CERTS_DIR/server-req.pem" \
    -CA "$CERTS_DIR/ca-cert.pem" \
    -CAkey "$CERTS_DIR/ca-key.pem" \
    -CAcreateserial \
    -out "$CERTS_DIR/server-cert.pem" \
    -extensions v3_req \
    -extfile "$CERTS_DIR/server-san.cnf"

# Установка правильных прав для серверного ключа
chmod 600 "$CERTS_DIR/server-key.pem"

# Генерация клиентских сертификатов для каждого пользователя
USERS=("apidoc" "apiman" "kpi")

for USER in "${USERS[@]}"; do
    echo "==> Создание клиентского сертификата для пользователя: $USER"
    
    # Создание директории для пользователя
    USER_DIR="$CERTS_DIR/client-$USER"
    mkdir -p "$USER_DIR"
    
    # Создание конфигурационного файла для клиентского сертификата
    cat > "$USER_DIR/$USER-client.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = RU
ST = Moscow
L = Moscow
O = Organization
OU = IT
CN = $USER

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF
    
    # Генерация приватного ключа и запроса на сертификат
    openssl req -new -nodes \
        -keyout "$USER_DIR/$USER-key.pem" \
        -out "$USER_DIR/$USER-req.pem" \
        -config "$USER_DIR/$USER-client.cnf"
    
    # Подписание клиентского сертификата CA с расширениями
    # -copy_extensions copyall копирует расширения из CSR
    openssl x509 -req -days 3650 \
        -in "$USER_DIR/$USER-req.pem" \
        -CA "$CERTS_DIR/ca-cert.pem" \
        -CAkey "$CERTS_DIR/ca-key.pem" \
        -CAcreateserial \
        -out "$USER_DIR/$USER-cert.pem" \
        -extfile "$USER_DIR/$USER-client.cnf" \
        -extensions v3_req
    
    # Копирование CA сертификата в директорию пользователя
    cp "$CERTS_DIR/ca-cert.pem" "$USER_DIR/"
    
    # Установка правильных прав
    chmod 600 "$USER_DIR/$USER-key.pem"
    chmod 644 "$USER_DIR/$USER-cert.pem"
    
    echo "    Сертификаты для $USER созданы в $USER_DIR"
done

# Очистка временных файлов
rm -f "$CERTS_DIR"/*.pem.srl
rm -f "$CERTS_DIR"/*.req
rm -f "$CERTS_DIR"/*.cnf
rm -f "$CERTS_DIR"/client-*/*-req.pem

echo ""
echo "==> Все сертификаты успешно созданы!"
echo "    CA: $CERTS_DIR/ca-cert.pem"
echo "    Сервер: $CERTS_DIR/server-cert.pem, $CERTS_DIR/server-key.pem"
echo "    Клиенты:"
for USER in "${USERS[@]}"; do
    echo "      $USER: $CERTS_DIR/client-$USER/"
done
