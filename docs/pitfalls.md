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

---

## 8. lua-resty-session 4.x と lua-resty-openidc 1.7.5 の非互換性

### 症状

nginx Pod で OIDC コールバックを処理するときに以下のエラーが出て 500 が返る。

```
lua entry thread aborted: runtime error: .../resty/session.lua:xxx:
attempt to index field 'identifiers' (a nil value)
no file '.../resty/session/identifiers/random.lua'
```

または、コールバックリクエストで `request to the redirect_uri path but there's no session state found` となり 401 が返る。

### 原因

`opm get bungle/lua-resty-session` はバージョン指定なしでは最新版 (4.x) をインストールする。
lua-resty-session 4.x は API が大幅に変更されており、lua-resty-openidc 1.7.5 が使用する 3.x の API
(`session.open()`, `session.data.*`, `session:save()`) と非互換である。

### 対処法

Dockerfile で opm を使って lua-resty-openidc をインストールした後、
lua-resty-session 3.10 (最後の 3.x リリース) を GitHub から手動で上書きインストールする。

opm はバージョン指定構文 (`@version`) をサポートしないため、手動取得が必要。

```dockerfile
RUN opm get ledgetech/lua-resty-http \
             zmartzone/lua-resty-openidc && \
    wget -qO /tmp/session.tar.gz \
         https://github.com/bungle/lua-resty-session/archive/refs/tags/v3.10.tar.gz && \
    tar -xzf /tmp/session.tar.gz -C /tmp && \
    rm -rf /usr/local/openresty/site/lualib/resty/session && \
    cp /tmp/lua-resty-session-3.10/lib/resty/session.lua \
       /usr/local/openresty/site/lualib/resty/session.lua && \
    cp -r /tmp/lua-resty-session-3.10/lib/resty/session \
          /usr/local/openresty/site/lualib/resty/ && \
    rm -rf /tmp/session.tar.gz /tmp/lua-resty-session-3.10
```

`rm -rf` で既存の 4.x ディレクトリを削除してから `cp -r` すること。
削除せずに `cp -r src dst` すると `dst` が既存の場合にネストされ (`dst/session/`) サブモジュールが見つからなくなる。

### 関連ファイル

- `apps/nginx/Dockerfile`

---

## 9. Keycloak 26 の KC_HOSTNAME に `host:port` 形式は不正

### 症状

Keycloak Pod が起動直後にクラッシュし、ログに以下が出る。

```
ERROR: Provided hostname is neither a plain hostname nor a valid URL
```

### 原因

Keycloak 26 の hostname v2 設定 (`KC_HOSTNAME`) には以下のいずれかを指定する必要がある。

- プレーンなホスト名: `keycloak.local`
- プロトコルを含む完全 URL: `http://keycloak.local:30080`

`keycloak.local:30080` のようなプロトコルなし host:port 形式は受け付けられない。

### 対処法

`values.yaml` の `keycloak.hostname` にプロトコルを含む完全 URL を設定する。

```yaml
keycloak:
  hostname: "http://keycloak.local:30080"
```

`KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true` と組み合わせることで、
discovery ドキュメントの `authorization_endpoint` は外部 URL (`http://keycloak.local:30080/...`)、
`token_endpoint` はリクエストの Host ヘッダーから内部 URL (`http://keycloak.authzen.svc.cluster.local:8080/...`) が動的に返される。

### 関連ファイル

- `charts/authzen/values.yaml` — `keycloak.hostname`
- `charts/authzen/templates/keycloak/deployment.yaml` — `KC_HOSTNAME`, `KC_HOSTNAME_BACKCHANNEL_DYNAMIC`

---

## 10. nginx-oidc-secret の client_secret が Keycloak の自動生成値と不一致

### 症状

OIDC コールバック時に以下のエラーが返り、トークン交換が失敗する。

```json
{"error":"unauthorized_client","error_description":"Invalid client or Invalid client credentials"}
```

### 原因

`nginx-oidc-secret` は手動で事前作成するが、デフォルト値が `CHANGE_ME` のまま。
Keycloak のレルムインポート時にクライアントシークレットが指定されていない場合、
Keycloak がランダム値を自動生成するため、Secret の値と一致しない。

### 対処法

`charts/authzen/templates/keycloak/realm-configmap.yaml` のクライアント定義に固定シークレットを指定し、
`values.yaml` の `keycloak.realm.client.secret` と `nginx-oidc-secret` を同じ値で揃える。

```yaml
# values.yaml
keycloak:
  realm:
    client:
      secret: "opatest-client-secret-changeme"
```

```bash
# nginx-oidc-secret 作成時
kubectl create secret generic nginx-oidc-secret \
  --from-literal=client_secret=opatest-client-secret-changeme \
  -n authzen
```

既存環境で Keycloak がすでに自動生成済みの場合は kcadm.sh で現在値を取得して Secret を更新する。

```bash
kubectl exec -n authzen deployment/keycloak -- \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password <password>

kubectl exec -n authzen deployment/keycloak -- \
  /opt/keycloak/bin/kcadm.sh get clients -r opatest --fields clientId,secret

kubectl patch secret nginx-oidc-secret -n authzen \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/data/client_secret\",\"value\":\"$(echo -n '<secret>' | base64)\"}]"
```

### 関連ファイル

- `charts/authzen/templates/keycloak/realm-configmap.yaml` — `"secret"` フィールド
- `charts/authzen/values.yaml` — `keycloak.realm.client.secret`
- `infra/k8s/minikube-setup.md` — Secret 作成手順

---

## 11. nginx Bearer トークンバイパスで OPA input が res を参照し続けるバグ

### 症状

Swagger UI や API クライアントから Bearer トークン付きリクエストを送ると 500 エラーになる。

```
lua entry thread aborted: runtime error: access_by_lua(...):
attempt to index global 'res' (a nil value)
```

### 原因

nginx Lua コードを「Bearer トークンがあれば OIDC セッションフローをスキップ」するよう変更した際、
OIDC フローの `res` オブジェクトから `token` 変数へ切り替えたが、
OPA へのリクエスト入力部分が `res.access_token` を参照したままになっていた。
Bearer パス (`token = auth_header:sub(8)`) では `res` が nil のためクラッシュする。

### 対処法

OPA input の token 参照を `res.access_token` から `token` 変数に統一する。

```lua
-- NG
local opa_input = cjson.encode({
  input = { token = res.access_token, ... }
})

-- OK
local opa_input = cjson.encode({
  input = { token = token, ... }
})
```

また、`openidc.authenticate()` が `nil, nil` を返す場合（コールバック処理後の内部リダイレクト等）への対処も必要。

```lua
local res, err = openidc.authenticate(opts)
if err then
  -- エラー処理 + ngx.exit()
end
if not res then
  return  -- openidc がレスポンス処理済み（リダイレクト等）
end
token = res.access_token
```

### 関連ファイル

- `charts/authzen/templates/nginx/configmap.yaml`

---

## 12. Swagger UI の API 呼び出しが CORS エラーになる (nginx モード)

### 症状

Swagger UI から API を実行すると "Failed to fetch" となる。

### 原因

nginx の OIDC フローはセッション/Cookie ベースのため、Bearer トークンなしの XHR リクエストに対して
Keycloak (`http://keycloak.local:30080`) へのリダイレクト (302) を返す。
XHR/fetch はクロスオリジンリダイレクトをブラウザが CORS ポリシーでブロックする。

### 対処法

nginx で `Authorization: Bearer` ヘッダーが存在する場合は OIDC セッションフローをスキップし、
トークンをそのまま OPA チェックに使用する。

```lua
local auth_header = ngx.req.get_headers()["Authorization"] or ""
if auth_header:sub(1, 7) == "Bearer " then
  token = auth_header:sub(8)  -- Bearer トークンをそのまま使用
else
  -- セッションベース OIDC フロー（ブラウザ向け）
  local res, err = openidc.authenticate(opts)
  ...
end
```

Swagger UI での使い方:
1. `https://authzen.local:30443/docs` を開く
2. 「Authorize」ボタンをクリックし、Keycloak から取得した access_token を入力
3. 以降のリクエストに `Authorization: Bearer <token>` が自動付与される

### 関連ファイル

- `charts/authzen/templates/nginx/configmap.yaml`
