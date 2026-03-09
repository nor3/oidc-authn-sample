#!/usr/bin/env bash
# E2Eテストスクリプト
# nginx経由でOIDC認証→OPA認可→バックエンドAPIの一連のフローをテストする
set -euo pipefail

PROFILE=authzen
BASE_URL="https://$(minikube ip --profile=$PROFILE):30443"
KEYCLOAK_URL="http://$(minikube ip --profile=$PROFILE):30080/auth"  # port-forward推奨
REALM=opatest
CLIENT_ID=opatest_client
CLIENT_SECRET="${OIDC_CLIENT_SECRET:-CHANGE_ME}"
TEST_USER=test
TEST_PASS=test
ADMIN_USER=admin-user
ADMIN_PASS=admin

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }

echo "=== AuthZEN E2E テスト ==="
echo "Base URL: $BASE_URL"
echo ""

# Keycloakからトークン取得 (Direct Grant)
get_token() {
  local username="$1"
  local password="$2"
  curl -s -X POST \
    "http://$(minikube ip --profile=$PROFILE):30080/realms/$REALM/protocol/openid-connect/token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "username=$username" \
    -d "password=$password" \
    -d "grant_type=password" \
    -d "scope=openid" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
}

echo "--- 1. トークン取得 ---"
TEST_TOKEN=$(get_token "$TEST_USER" "$TEST_PASS")
if [ -n "$TEST_TOKEN" ]; then
  pass "testユーザトークン取得"
else
  fail "testユーザトークン取得失敗"
  exit 1
fi

ADMIN_TOKEN=$(get_token "$ADMIN_USER" "$ADMIN_PASS")
if [ -n "$ADMIN_TOKEN" ]; then
  pass "admin-userトークン取得"
else
  fail "admin-userトークン取得失敗"
fi

echo ""
echo "--- 2. GET /api/v1/documents (viewer権限でアクセス) ---"
STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TEST_TOKEN" \
  "$BASE_URL/api/v1/documents")
[ "$STATUS" = "200" ] && pass "GET 200" || fail "GET $STATUS (期待: 200)"

echo ""
echo "--- 3. POST /api/v1/documents (editor権限でアクセス) ---"
STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"E2E Test","content":"test content"}' \
  "$BASE_URL/api/v1/documents")
[ "$STATUS" = "201" ] && pass "POST 201" || fail "POST $STATUS (期待: 201)"

echo ""
echo "--- 4. DELETE (testユーザ=editor、admin権限なし → 403) ---"
# まずドキュメントIDを取得
DOC_ID=$(curl -sk \
  -H "Authorization: Bearer $TEST_TOKEN" \
  "$BASE_URL/api/v1/documents" | python3 -c "import sys,json; docs=json.load(sys.stdin); print(docs[0]['id'] if docs else '')")

if [ -n "$DOC_ID" ]; then
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer $TEST_TOKEN" \
    "$BASE_URL/api/v1/documents/$DOC_ID")
  [ "$STATUS" = "403" ] && pass "DELETE 403 (正常: testユーザは削除不可)" || fail "DELETE $STATUS (期待: 403)"

  echo ""
  echo "--- 5. DELETE (admin-userは削除可能 → 204) ---"
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$BASE_URL/api/v1/documents/$DOC_ID")
  [ "$STATUS" = "204" ] && pass "DELETE 204 (admin-userは削除可能)" || fail "DELETE $STATUS (期待: 204)"
fi

echo ""
echo "=== テスト結果 ==="
echo "  成功: $PASS"
echo "  失敗: $FAIL"
echo ""
[ "$FAIL" -eq 0 ] && echo "全テスト成功！" || { echo "失敗したテストがあります。"; exit 1; }
