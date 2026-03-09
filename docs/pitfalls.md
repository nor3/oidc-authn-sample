# 既知のあい路事項 (Pitfalls)

開発・運用中に遭遇した落とし穴と対処法を記録する。

---

## 1. nginx (OpenResty) の Lua から環境変数が取得できない

### 症状

nginx Pod のログに以下のようなエラーが出力され、500 が返る。

```
lua entry thread aborted: runtime error: .../resty/openidc.lua:661:
attempt to index field 'discovery' (a nil value)
```

`os.getenv("OIDC_DISCOVERY_URL")` が `nil` を返すため、
`lua-resty-openidc` の discovery フェッチがスキップされ、
`opts.discovery` が nil のまま内部処理に渡されクラッシュする。

### 原因

nginx は**セキュリティ上の設計として、起動時にワーカープロセスへ渡す環境変数を全て削除する**。
コンテナの環境変数として Pod に正しく設定されていても、`nginx.conf` に明示宣言しない限り
Lua コード (`os.getenv`) からは参照できない。

> 公式ドキュメント: https://nginx.org/en/docs/ngx_core_module.html#env

`resty` CLI ではシェルの環境変数を直接引き継ぐため正常に取得できるが、
nginx ワーカー経由のリクエスト処理では取得できない。これがデバッグを困難にする。

### 対処法

`nginx.conf` のメインブロック（`http` ブロックや `events` より前）に
使用する環境変数を `env` ディレクティブで宣言する。

```nginx
# nginx は起動時に環境変数を削除するため、使用する変数を明示的に宣言する
env OIDC_DISCOVERY_URL;
env OIDC_CLIENT_ID;
env OIDC_CLIENT_SECRET;
env OIDC_REDIRECT_URI;
env OPA_URL;
env OPA_POLICY_PATH;
```

本プロジェクトでは `charts/authzen/templates/nginx/configmap.yaml` の
`nginx.conf` 冒頭に記載済み。新しい環境変数を追加する場合は必ずここにも追記する。

### 関連ファイル

- `charts/authzen/templates/nginx/configmap.yaml` — `env` ディレクティブの宣言箇所
- `charts/authzen/templates/nginx/deployment.yaml` — 環境変数の設定箇所

---

## 2. ConfigMap 変更時に nginx Pod が自動再起動されない

### 症状

`helm upgrade` で `nginx.conf`（ConfigMap）を変更しても、
nginx Pod が再起動されず古い設定が使われ続ける。

### 原因

Kubernetes は ConfigMap の変更を Deployment のローリングアップデートトリガーとして扱わない。
Deployment の Pod template spec が変わらない限り、新しい Pod は作成されない。

### 対処法

Deployment の Pod template annotation に ConfigMap の `sha256sum` を埋め込む。
ConfigMap の内容が変わると annotation の値が変わり、Deployment のローリングアップデートが自動で発動する。

```yaml
template:
  metadata:
    annotations:
      checksum/config: {{ include (print $.Template.BasePath "/nginx/configmap.yaml") . | sha256sum }}
```

本プロジェクトでは `charts/authzen/templates/nginx/deployment.yaml` に適用済み。

---

## 3. lua-resty-openidc の `token_endpoint` オプションが discovery をスキップする

### 症状

lua-resty-openidc の opts に `token_endpoint` を設定すると、
`opts.discovery` が nil のまま内部処理が進みクラッシュする（症状は上記 #1 と同一）。

### 原因

lua-resty-openidc 1.7.5 では、opts に `token_endpoint` が設定されている場合、
`openidc_ensure_discovered_data` が discovery のフェッチをスキップするコードパスがある。
その後 `openidc_get_token_auth_method` が `opts.discovery` を参照しクラッシュする。

### 対処法

`token_endpoint` を opts で上書きしない。
Keycloak の discovery ドキュメントが内部 URL (`http://keycloak:8080/...`) を返す構成であれば、
OpenResty は discovery 経由で正しいトークンエンドポイントを自動取得できる。

---

## 4. OPA イメージタグに `-rootless` サフィックスは存在しない

### 症状

OPA Pod が `ImagePullBackOff` になる。

```
Failed to pull image "openpolicyagent/opa:0.70.0-rootless":
manifest unknown: manifest unknown
```

### 原因

`openpolicyagent/opa` の Docker Hub イメージに `-rootless` バリアントは存在しない。

### 対処法

`values.yaml` の `opa.image.tag` からサフィックスを除く。

```yaml
opa:
  image:
    tag: "1.14.1"   # "-rootless" は不要
```

---

## 6. nginx の `resolver` にホスト名を指定すると DNS 解決が失敗する

### 症状

nginx ログに以下のエラーが出て、Keycloak への接続が失敗し 401 が返る。

```
keycloak could not be resolved (2: Server failure)
unexpected DNS response for keycloak
```

### 原因

nginx の `resolver` ディレクティブは **IP アドレスのみ受け付ける**。
ホスト名（例: `kube-dns.kube-system.svc.cluster.local`）を指定しても解決できず、
Lua コードからの名前解決が全て失敗する。

### なぜ `kube-dns.kube-system.svc.cluster.local` も使えないか

nginx の `resolver` ディレクティブは **IP アドレスのみ受け付ける**。ホスト名を指定すると
「ホスト名を解決するために、まずそのホスト名を解決する」という循環参照になるため機能しない。

### 対処法

コンテナ起動時に `/etc/resolv.conf` から nameserver を読み取り、nginx.conf テンプレートに注入する。

```sh
NAMESERVER=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
sed "s/__NAMESERVER__/$NAMESERVER/g" /etc/nginx-template/nginx.conf \
  > /usr/local/openresty/nginx/conf/nginx.conf
exec /usr/local/openresty/bin/openresty -g 'daemon off;'
```

`/etc/resolv.conf` は Kubernetes がポッド起動時に kube-dns の正しい ClusterIP を書き込むため、
クラスタ間での移植性も保たれる。

### 関連ファイル

- `charts/authzen/templates/nginx/deployment.yaml` — `command` で起動時注入
- `charts/authzen/templates/nginx/configmap.yaml` — `resolver __NAMESERVER__` プレースホルダー

---

## 7. nginx の `resolver` は `/etc/resolv.conf` の search ドメインを使わない

### 症状

resolver に正しい kube-dns IP を設定しても、`keycloak` など短いホスト名の解決が失敗する。

```
keycloak could not be resolved (2: Server failure)
```

### 原因

Pod の `/etc/resolv.conf` には以下のような search ドメインが設定されており、
`nslookup keycloak` などは `keycloak.authzen.svc.cluster.local` として解決される。

```
search authzen.svc.cluster.local svc.cluster.local cluster.local
```

しかし nginx の `resolver` は **この search ドメインを使わない**。
`keycloak` だけを DNS に問い合わせると SERVFAIL になる。

### 対処法

nginx の lua コードから参照する内部ホスト名はすべて FQDN で指定する。

```
# NG
http://keycloak:8080/...
http://opa:8181/...

# OK
http://keycloak.authzen.svc.cluster.local:8080/...
http://opa.authzen.svc.cluster.local:8181/...
```

本プロジェクトでは `charts/authzen/values.yaml` の各 URL に FQDN を設定済み。
namespace を変更した場合は URL も合わせて変更すること。

### 関連ファイル

- `charts/authzen/values.yaml` — `nginx.oidc.discoveryUrl`, `nginx.opa.url`

---

## 5. OPA が ConfigMap をディレクトリマウントすると同一ポリシーを二重読み込みする

### 症状

OPA Pod が `CrashLoopBackOff` になり、以下のエラーが出る。

```
rego_type_error: multiple default rules data.authzen.api.allow found
```

### 原因

Kubernetes の ConfigMap をディレクトリとしてマウントすると、
シンボリックリンク (`authzen.rego → ..data/authzen.rego`) と
タイムスタンプ付きの実体ディレクトリ (`..2026_.../authzen.rego`) が共存する。
OPA が `/policies` を再帰的に監視・読み込む際に同一ファイルを二重に取り込み、
`default allow` が重複してエラーになる。

### 対処法

`subPath` を使いポリシーファイルを単一ファイルとしてマウントする。
これによりシンボリックリンク構造が作られず、OPA は一度だけ読み込む。

```yaml
volumeMounts:
  - name: policy
    mountPath: /policies/authzen.rego
    subPath: authzen.rego
```

また OPA の args もディレクトリではなくファイルを直接指定する。

```yaml
args:
  - run
  - --server
  - --addr=0.0.0.0:8181
  - /policies/authzen.rego
```

本プロジェクトでは `charts/authzen/templates/opa/deployment.yaml` に適用済み。
