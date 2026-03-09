#!/usr/bin/env bash
# ローカル環境の完全リセットスクリプト
set -euo pipefail

NAMESPACE=authzen
RELEASE=authzen
PROFILE=authzen

echo "=== Helmリリースの削除 ==="
helm uninstall "$RELEASE" -n "$NAMESPACE" --ignore-not-found

echo ""
echo "=== Namespaceの削除 ==="
kubectl delete namespace "$NAMESPACE" --ignore-not-found

echo ""
echo "=== CloudNativePG PVCの削除 ==="
kubectl delete pvc -l cnpg.io/cluster=keycloak-pg -n "$NAMESPACE" --ignore-not-found || true

echo ""
echo "=== minikubeの停止 ==="
read -r -p "minikubeクラスタも削除しますか? (y/N): " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  minikube delete --profile="$PROFILE"
  echo "minikubeクラスタを削除しました。"
else
  echo "minikubeクラスタは保持します。"
fi

echo ""
echo "リセット完了。"
