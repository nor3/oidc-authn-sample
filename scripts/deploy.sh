#!/usr/bin/env bash
# authzen Helmデプロイスクリプト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE=authzen
RELEASE=authzen
CHART="$PROJECT_DIR/charts/authzen"
PROFILE=authzen

echo "=== OPAポリシーのSyntax Check ==="
OPA_TAG=$(grep -A10 '^opa:' "$CHART/values.yaml" | grep 'tag:' | head -1 | awk '{print $2}' | tr -d '"')
docker run --rm \
  -v "$PROJECT_DIR/policies/opa:/work:ro" \
  "openpolicyagent/opa:$OPA_TAG" check /work/authzen.rego || {
    echo "エラー: Regoポリシーのチェックに失敗しました: policies/opa/authzen.rego"
    exit 1
  }
echo "Syntax Check OK"

echo ""
echo "=== minikube Docker環境に切り替え ==="
eval "$(minikube docker-env --profile=$PROFILE)"

echo ""
echo "=== Dockerイメージのビルド ==="
docker build -t authzen/backend:latest "$PROJECT_DIR/apps/backend/"
docker build -t authzen/nginx:latest   "$PROJECT_DIR/apps/nginx/"

echo ""
echo "=== Namespace の確認・作成 ==="
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  # 既存 Namespace を Helm に採用させる (ownership メタデータを付与)
  # templates/namespace.yaml を持たないため通常は不要だが、
  # 過去に chart で作成した場合の残留メタデータを除去するための保険
  echo "Namespace '$NAMESPACE' は既に存在します。"
else
  kubectl create namespace "$NAMESPACE"
  echo "Namespace '$NAMESPACE' を作成しました。"
fi

echo ""
echo "=== Secrets の検証 ==="
# proxy.mode を values.yaml から読み取る
PROXY_MODE=$(grep '^  mode:' "$CHART/values.yaml" | head -1 | awk '{print $2}')
REQUIRED_SECRETS=(authzen-tls nginx-oidc-secret keycloak-admin-secret)
if [ "$PROXY_MODE" = "oauth2proxy" ]; then
  REQUIRED_SECRETS+=(oauth2proxy-cookie-secret)
fi
MISSING=()
for secret in "${REQUIRED_SECRETS[@]}"; do
  if ! kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
    MISSING+=("$secret")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "エラー: 以下の Secret が存在しません:"
  for s in "${MISSING[@]}"; do echo "  - $s"; done
  echo ""
  echo "infra/k8s/minikube-setup.md の手順で Secret を作成してから再実行してください。"
  exit 1
fi
echo "全 Secret を確認しました。"

echo ""
echo "=== Helm デプロイ ==="
# --set-file でポリシーを chart 外から渡す (.Files.Get は chart 外不可のため)
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --set-file "opa.policy=$PROJECT_DIR/policies/opa/authzen.rego" \
  --wait \
  --timeout 5m || {
    echo ""
    echo "=== デプロイ失敗時の調査コマンド ==="
    echo "kubectl get pods -n $NAMESPACE"
    echo "kubectl describe pod -n $NAMESPACE -l app=nginx"
    echo "kubectl describe pod -n $NAMESPACE -l app=opa"
    echo "kubectl logs -n $NAMESPACE -l app=nginx --previous"
    echo "kubectl logs -n $NAMESPACE -l app=opa"
    exit 1
  }

echo ""
echo "=== backend ローリング再起動 (latest イメージ反映) ==="
kubectl rollout restart deployment/backend -n "$NAMESPACE"
kubectl rollout status deployment/backend -n "$NAMESPACE" --timeout=60s

echo ""
echo "=== デプロイ状況 ==="
kubectl get pods -n "$NAMESPACE"

echo ""
echo "=== アクセスURL ==="
MINIKUBE_IP="$(minikube ip --profile=$PROFILE)"
if [ "$PROXY_MODE" = "oauth2proxy" ]; then
  echo "  https://$MINIKUBE_IP:30443  (oauth2-proxy HTTPS / ingress TLS終端)"
else
  echo "  https://$MINIKUBE_IP:30443  (nginx HTTPS)"
  echo "  http://$MINIKUBE_IP:30080   (nginx HTTP → HTTPS redirect)"
fi
echo ""
echo "デプロイ完了。 (proxy.mode=$PROXY_MODE)"
