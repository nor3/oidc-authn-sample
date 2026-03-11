HELM_RELEASE   := authzen
HELM_CHART     := charts/authzen
NAMESPACE      := authzen
MINIKUBE_PROF  := authzen

.PHONY: help certs minikube-start minikube-stop deploy undeploy \
        policy-check policy-update tunnel test test-e2e keycloak-setup logs clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  %-20s %s\n", $$1, $$2}'

certs: ## TLS証明書を生成する
	bash scripts/generate-certs.sh

minikube-start: ## minikubeクラスタを起動する
	minikube start --profile=$(MINIKUBE_PROF) --driver=docker \
	  --cpus=4 --memory=8192 --addons=ingress
	minikube profile $(MINIKUBE_PROF)

minikube-stop: ## minikubeクラスタを停止する
	minikube stop --profile=$(MINIKUBE_PROF)

deploy: ## Helmチャートをデプロイする
	bash scripts/deploy.sh

undeploy: ## Helmリリースを削除する
	helm uninstall $(HELM_RELEASE) -n $(NAMESPACE) --ignore-not-found
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

tunnel: ## WindowsホストからのアクセスURL等を表示する (実行はWindows側スクリプトで)
	@echo "Windows PowerShell (管理者) で以下を実行してください:"
	@echo ""
	@echo "  .\\scripts\\tunnel.ps1"
	@echo ""
	@echo "スクリプトが以下を自動で行います:"
	@echo "  1. WSL2 内で kubectl port-forward を起動"
	@echo "  2. netsh portproxy で Windows localhost -> WSL2 IP に転送"
	@echo "  3. Windows hosts ファイルへのホスト名追加"
	@echo ""
	@echo "【アクセスURL】"
	@echo "  アプリ:          https://authzen.local"
	@echo "  Keycloak 管理:   https://keycloak.local"

policy-check: ## OPAポリシーのSyntax Checkを実行する
	@OPA_TAG=$$(grep -A10 '^opa:' $(HELM_CHART)/values.yaml | grep 'tag:' | head -1 | awk '{print $$2}' | tr -d '"'); \
	echo "OPA $${OPA_TAG} でポリシーをチェック中: policies/opa/authzen.rego"; \
	docker run --rm \
	  -v "$(PWD)/policies/opa:/work:ro" \
	  openpolicyagent/opa:$${OPA_TAG} check /work/authzen.rego && \
	echo "OK: Syntax Check 通過"

policy-update: policy-check ## OPAポリシーをConfigMapから更新する
	kubectl create configmap opa-policy \
	  --from-file=policies/opa/ \
	  -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

test: ## バックエンドユニットテストを実行する
	cd apps/backend && python -m pytest tests/ -v

test-e2e: ## E2Eテストを実行する
	bash scripts/test-e2e.sh

keycloak-setup: ## Keycloak設定の確認
	@echo "Keycloak URL: https://$$(minikube ip)/auth"
	@echo "Admin: admin / admin (開発用)"
	@echo "Realm: opatest  Client: opatest_client  User: test/test"

build-backend: ## バックエンドDockerイメージをビルドする
	eval $$(minikube docker-env  --profile=$(MINIKUBE_PROF)) && \
	  docker build -t authzen/backend:latest apps/backend/

build-nginx: ## Nginxイメージをビルドする
	eval $$(minikube docker-env) && \
	  docker build -t authzen/nginx:latest apps/nginx/

build: build-backend build-nginx ## 全イメージをビルドする

logs-backend: ## バックエンドのログを表示する
	kubectl logs -n $(NAMESPACE) -l app=backend -f

logs-nginx: ## Nginxのログを表示する
	kubectl logs -n $(NAMESPACE) -l app=nginx -f

logs-opa: ## OPAのログを表示する
	kubectl logs -n $(NAMESPACE) -l app=opa -f

clean: ## 証明書・一時ファイルを削除する
	rm -f certs/*.pem certs/*.crt certs/*.key certs/*.csr
	bash scripts/reset-env.sh
