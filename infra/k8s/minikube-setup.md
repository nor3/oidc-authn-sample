# Minikube セットアップ手順

## 前提条件

- minikube >= 1.33
- helm >= 3.15
- kubectl >= 1.30
- Docker Desktop (Windows) または docker (Linux/Mac)
- openssl

## 1. CloudNativePG Operator のインストール

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.24.0.yaml

# 確認
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system --timeout=120s
```

## 2. minikube クラスタの起動

```bash
minikube start --profile=authzen \
  --driver=docker \
  --cpus=4 \
  --memory=8192
```

## 3. TLS 証明書の生成

```bash
bash scripts/generate-certs.sh
```

## 4. Kubernetes Secrets の作成

```bash
NAMESPACE=authzen
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# TLS証明書 (fullchain = server.crt + ca.crt)
# nginx がチェーンごと送信することで curl/ブラウザが CA を辿れる
kubectl create secret tls authzen-tls \
  --cert=certs/fullchain.crt \
  --key=certs/server.key \
  -n $NAMESPACE

# Nginx OIDCクライアントシークレット
# values.yaml の keycloak.realm.client.secret と同じ値を設定すること
kubectl create secret generic nginx-oidc-secret \
  --from-literal=client_secret=opatest-client-secret-changeme \
  -n $NAMESPACE

# Keycloak adminパスワード
kubectl create secret generic keycloak-admin-secret \
  --from-literal=password=admin \
  -n $NAMESPACE

# testユーザパスワード
kubectl create secret generic keycloak-test-user-secret \
  --from-literal=password=test \
  -n $NAMESPACE

# oauth2-proxy クッキー暗号化シークレット (proxy.mode: oauth2proxy の場合のみ必要)
# 32バイトのランダム値を base64 エンコードして設定する
COOKIE_SECRET=$(openssl rand -base64 32 | tr -d '\n')
kubectl create secret generic oauth2proxy-cookie-secret \
  --from-literal=cookie_secret="$COOKIE_SECRET" \
  -n $NAMESPACE
```

## 5. Helm デプロイ

```bash
bash scripts/deploy.sh
```

## 6. アクセス確認

```bash
# minikube IP の確認
minikube ip --profile=authzen

# /etc/hosts に追加 (Windows: C:\Windows\System32\drivers\etc\hosts)
# <MINIKUBE_IP> authzen.local

# ブラウザで https://authzen.local にアクセス
# → Keycloak ログイン画面にリダイレクトされる
# ユーザ: test / test
```

## トラブルシューティング

### Keycloak が起動しない

CloudNativePG クラスタが準備完了になるまで時間がかかる場合がある:

```bash
kubectl get cluster -n authzen
kubectl describe pod -l app=keycloak -n authzen
```

### OPA ポリシーの確認

```bash
kubectl exec -n authzen deploy/opa -- \
  opa eval -d /policies -I 'data.authzen.api.allow' \
  --input '{"token":"...","method":"GET","path":"/api/v1/documents"}'
```

### nginx ログの確認

```bash
kubectl logs -n authzen -l app=nginx -f
```
