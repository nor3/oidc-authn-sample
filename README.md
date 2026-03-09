# AuthZEN Demo

OPA認可とKeycloak/Nginxを組み合わせたKubernetes上の認可デモ。

## アーキテクチャ

```
Client → Nginx(PEP/OIDC Proxy) → OPA(PDP) → Backend(FastAPI)
                ↕
           Keycloak(IdP)
```

## 前提条件

- minikube >= 1.33
- helm >= 3.15
- kubectl >= 1.30
- openssl (証明書生成)
- Python >= 3.12 (ローカル開発)

## クイックスタート

```bash
# 1. 証明書生成
make certs

# 2. minikube起動
make minikube-start

# 3. デプロイ
make deploy

# 4. Keycloak設定確認
make keycloak-setup

# 5. E2Eテスト実行
make test-e2e
```

## 詳細な起動手順

[infra/k8s/minikube-setup.md](infra/k8s/minikube-setup.md) を参照。

## 開発

### バックエンドサービス

[apps/backend/README.md](apps/backend/README.md) を参照。

### ポリシー更新

`policies/opa/` 配下の `.rego` ファイルを編集後:

```bash
make policy-update
```

## プロジェクト構造

```
authzen/
├── apps/
│   ├── backend/       # FastAPI サービス
│   └── nginx/         # OpenResty (OIDC Proxy + PEP)
├── charts/authzen/    # Helm chart
├── policies/opa/      # Rego ポリシー
├── infra/k8s/         # 補助 K8s マニフェスト
├── scripts/           # デプロイ・管理スクリプト
├── certs/             # TLS 証明書
└── tests/             # E2E・インテグレーションテスト
```
