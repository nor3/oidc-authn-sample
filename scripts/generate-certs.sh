#!/usr/bin/env bash
# TLS証明書生成スクリプト (プライベートCA + サーバ証明書)
set -euo pipefail

CERTS_DIR="$(cd "$(dirname "$0")/../certs" && pwd)"
CA_KEY="$CERTS_DIR/ca.key"
CA_CERT="$CERTS_DIR/ca.crt"
SERVER_KEY="$CERTS_DIR/server.key"
SERVER_CSR="$CERTS_DIR/server.csr"
SERVER_CERT="$CERTS_DIR/server.crt"
FULLCHAIN="$CERTS_DIR/fullchain.crt"  # server.crt + ca.crt (nginx用)
DAYS=3650

mkdir -p "$CERTS_DIR"

echo "=== プライベートCA証明書の生成 ==="
if [ ! -f "$CA_KEY" ]; then
  openssl genrsa -out "$CA_KEY" 4096

  # basicConstraints=CA:true と keyUsage を明示することで
  # OpenSSL / curl / ブラウザが CA として正しく認識する
  openssl req -x509 -new -nodes \
    -key "$CA_KEY" \
    -sha256 \
    -days "$DAYS" \
    -out "$CA_CERT" \
    -subj "/CN=AuthZEN-CA/O=AuthZEN Demo/C=JP" \
    -addext "basicConstraints=critical,CA:true" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash"

  echo "CA証明書を生成しました: $CA_CERT"
else
  echo "CA証明書は既に存在します: $CA_KEY"
fi

echo ""
echo "=== サーバ証明書の生成 ==="
openssl genrsa -out "$SERVER_KEY" 2048

openssl req -new \
  -key "$SERVER_KEY" \
  -out "$SERVER_CSR" \
  -subj "/CN=authzen.local/O=AuthZEN Demo/C=JP"

# SAN + TLS用拡張
cat > "$CERTS_DIR/server_ext.cnf" <<EOF
[v3_req]
basicConstraints = CA:false
keyUsage         = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt_names

[alt_names]
DNS.1 = authzen.local
DNS.2 = keycloak.local
DNS.3 = localhost
IP.1  = 127.0.0.1
EOF

openssl x509 -req \
  -in "$SERVER_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$SERVER_CERT" \
  -days "$DAYS" \
  -sha256 \
  -extfile "$CERTS_DIR/server_ext.cnf" \
  -extensions v3_req

rm -f "$CERTS_DIR/server_ext.cnf"

# nginx に渡すフルチェーン (server.crt + ca.crt)
# TLS handshake で CA チェーンまで送ることで curl/ブラウザが検証できる
cat "$SERVER_CERT" "$CA_CERT" > "$FULLCHAIN"

echo ""
echo "=== 生成された証明書 ==="
echo "  CA証明書:         $CA_CERT"
echo "  サーバ証明書:     $SERVER_CERT"
echo "  フルチェーン:     $FULLCHAIN  ← kubectl secret tls に使用"
echo "  サーバ鍵:         $SERVER_KEY"
echo ""
echo "=== CA証明書のインポート (OSによって選択) ==="
echo ""
echo "  [Windows] 管理者 PowerShell または cmd で実行:"
echo "    certutil -addstore Root \"$(cygpath -w "$CA_CERT" 2>/dev/null || echo "$CA_CERT")\""
echo ""
echo "  [Mac]:"
echo "    sudo security add-trusted-cert -d -r trustRoot \\"
echo "      -k /Library/Keychains/System.keychain $CA_CERT"
echo ""
echo "  [Linux/WSL]:"
echo "    sudo cp $CA_CERT /usr/local/share/ca-certificates/authzen.crt"
echo "    sudo update-ca-certificates"
echo ""
echo "  [curl で即時テスト (インポート不要)]:"
echo "    curl --cacert $CA_CERT https://authzen.local"
