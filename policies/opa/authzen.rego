package authzen.api

import rego.v1

# デフォルト: 拒否
default allow := false

# ===================================================
# メインルール: 認証済みかつ必要なロールを持つ場合に許可
# ===================================================
allow if {
    token := decoded_token
    required_role := method_role[input.method]
    required_role in token_roles(token)
}

# ===================================================
# HTTPメソッドと必要ロールのマッピング
# ===================================================
method_role := {
    "GET":    "viewer",
    "HEAD":   "viewer",
    "OPTIONS":"viewer",
    "POST":   "editor",
    "PUT":    "editor",
    "PATCH":  "editor",
    "DELETE": "admin",
}

# ===================================================
# JWT デコード (Keycloak 発行トークン)
# input.token: Authorization ヘッダの Bearer トークン文字列
# ===================================================
decoded_token := payload if {
    [_, payload, _] := io.jwt.decode(input.token)
}

# ===================================================
# ロール抽出
# Keycloak は realm_access.roles にレルムロールを格納する
# ===================================================
token_roles(token) := roles if {
    roles := token.realm_access.roles
}

# カスタムクレームのフォールバック
token_roles(token) := roles if {
    not token.realm_access
    roles := token.roles
}

# ===================================================
# デバッグ用: 評価に使ったロール一覧を返す (OPA /v1/data で参照)
# ===================================================
debug := {
    "subject": decoded_token.sub,
    "roles":   token_roles(decoded_token),
    "method":  input.method,
    "path":    input.path,
    "allow":   allow,
}
