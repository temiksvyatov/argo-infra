#!/bin/bash
set -e

# Директория для сертификатов
CERTS_DIR="./certs"
mkdir -p "$CERTS_DIR"

echo "==> Генерация сертификатов для PostgreSQL с mTLS (v2 - для Istio)"

# Создание CA конфигурации
cat > "$CERTS_DIR/ca.cnf" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir = $CERTS_DIR
database = \$dir/index.txt
new_certs_dir = \$dir/newcerts
certificate = \$dir/ca-cert.pem
private_key = \$dir/ca-key.pem
serial = \$dir/serial
default_md = sha256
preserve = no
policy = policy_anything
default_days = 3650

[ policy_anything ]
countryName = optional
stateOrProvinceName = optional
localityName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional

[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[ req_distinguished_name ]
countryName = Country Name (2 letter code)
countryName_default = RU
stateOrProvinceName = State or Province Name
stateOrProvinceName_default = Moscow
localityName = Locality Name
localityName_default = Moscow
organizationName = Organization Name
organizationName_default = Organization
commonName = Common Name
commonName_max = 64

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ client_cert ]
basicConstraints = CA:FALSE
nsCertType = client
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

# Генерация CA
echo "==> Создание CA сертификата..."
openssl req -new -x509 -days 3650 -nodes \
    -keyout "$CERTS_DIR/ca-key.pem" \
    -out "$CERTS_DIR/ca-cert.pem" \
    -config "$CERTS_DIR/ca.cnf" \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=Organization/OU=IT/CN=PostgreSQL-CA"

# Инициализация CA структуры
mkdir -p "$CERTS_DIR/newcerts"
touch "$CERTS_DIR/index.txt"
echo "01" > "$CERTS_DIR/serial"

# Генерация серверного сертификата
echo "==> Создание серверного сертификата..."
CUSTOM_HOSTNAME="${1:-srv8-objkrugess.mfactory.nxcloud.nexign.com}"

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

openssl req -new -nodes \
    -keyout "$CERTS_DIR/server-key.pem" \
    -out "$CERTS_DIR/server-req.pem" \
    -config "$CERTS_DIR/server-san.cnf"

openssl ca -batch -config "$CERTS_DIR/ca.cnf" \
    -extensions server_cert \
    -extfile "$CERTS_DIR/server-san.cnf" \
    -out "$CERTS_DIR/server-cert.pem" \
    -infiles "$CERTS_DIR/server-req.pem"

chmod 600 "$CERTS_DIR/server-key.pem"

# Генерация клиентских сертификатов
USERS=("apidoc" "apiman" "kpi")

for USER in "${USERS[@]}"; do
    echo "==> Создание клиентского сертификата для пользователя: $USER"
    
    USER_DIR="$CERTS_DIR/client-$USER"
    mkdir -p "$USER_DIR"
    
    # Генерация ключа и CSR
    openssl req -new -nodes \
        -keyout "$USER_DIR/$USER-key.pem" \
        -out "$USER_DIR/$USER-req.pem" \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=Organization/OU=IT/CN=$USER"
    
    # Подписание через CA
    openssl ca -batch -config "$CERTS_DIR/ca.cnf" \
        -extensions client_cert \
        -out "$USER_DIR/$USER-cert.pem" \
        -infiles "$USER_DIR/$USER-req.pem"
    
    cp "$CERTS_DIR/ca-cert.pem" "$USER_DIR/"
    chmod 600 "$USER_DIR/$USER-key.pem"
    chmod 644 "$USER_DIR/$USER-cert.pem"
    
    echo "    Сертификаты для $USER созданы"
done

# Очистка
rm -f "$CERTS_DIR"/*.cnf
rm -f "$CERTS_DIR"/*.req
rm -f "$CERTS_DIR"/client-*/*-req.pem
rm -rf "$CERTS_DIR/newcerts"
rm -f "$CERTS_DIR/index.txt"*
rm -f "$CERTS_DIR/serial"*

echo ""
echo "==> Все сертификаты успешно созданы!"
