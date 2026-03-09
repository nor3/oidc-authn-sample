# AuthZEN Backend

OPA認可デモ用 FastAPI サービス。

## ローカル開発

```bash
# 依存パッケージインストール
pip install -e ".[dev]"

# 開発サーバ起動
uvicorn src.main:app --reload --port 8000

# テスト実行
pytest tests/ -v
```

## 環境変数

| 変数名           | デフォルト                        | 説明                                     |
|-----------------|----------------------------------|------------------------------------------|
| `OPA_MIDDLEWARE` | `false`                          | OPAミドルウェアの有効化                   |
| `OPA_URL`        | `http://opa:8181`                | OPAサービスのURL                          |
| `OPA_POLICY_PATH`| `v1/data/authzen/api/allow`      | OPAポリシーのパス                         |
| `DEBUG`          | `false`                          | デバッグモード                            |

## OPA ミドルウェアモード

`OPA_MIDDLEWARE=true` に設定すると、nginx の auth_request を使わずに
バックエンド自身がOPAに認可チェックを行うミドルウェアモードで動作する。

```bash
OPA_MIDDLEWARE=true OPA_URL=http://localhost:8181 uvicorn src.main:app --reload
```

## APIエンドポイント

`docs/api-spec.yaml` を参照。Swagger UI は `http://localhost:8000/docs` で確認可能。

## ロール

| ロール   | 許可操作           |
|---------|-------------------|
| viewer  | GET               |
| editor  | GET, POST, PUT    |
| admin   | 全操作 (DELETE含む)|
