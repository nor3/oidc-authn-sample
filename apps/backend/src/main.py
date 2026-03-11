from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPBearer

from .config import settings
from .middleware.opa import OPAMiddleware
from .routers import documents, health

# Swagger UI に "Authorize" ボタンを表示するための Bearer トークンスキーム
# auto_error=False: トークン未提供でも FastAPI レベルでは弾かない (認可は middleware に委譲)
_bearer = HTTPBearer(auto_error=False)

app = FastAPI(
    title=settings.app_name,
    description="OPA認可デモ用サンプルREST API",
    version="1.0.0",
    dependencies=[Depends(_bearer)],
    docs_url=None,  # カスタム Swagger UI を使うため無効化
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

if settings.opa_middleware:
    app.add_middleware(
        OPAMiddleware,
        opa_url=settings.opa_url,
        policy_path=settings.opa_policy_path,
        skip_patterns=[
            "/health",
            "/health/*",
            "/docs",
            "/docs/*",
            "/redoc",
            "/openapi.json",
            "/auth/token",
        ],
    )

app.include_router(health.router)
app.include_router(documents.router, prefix="/api/v1")


@app.get("/auth/token", include_in_schema=False)
async def get_token(request: Request):
    """nginx が注入した Authorization ヘッダからトークンを返す。Swagger UI 自動認証用。"""
    auth = request.headers.get("authorization", "")
    token = auth.removeprefix("Bearer ").removeprefix("bearer ").strip()
    return {"token": token}


@app.get("/docs", include_in_schema=False)
async def custom_swagger_ui(request: Request) -> HTMLResponse:
    """nginx の OIDC トークンを自動取得して Swagger UI に設定するカスタム UI。"""
    html = get_swagger_ui_html(
        openapi_url="/openapi.json",
        title=settings.app_name,
    )
    # onComplete フックを注入してトークンを自動設定する
    auto_auth_script = """
    <script>
    (function() {
      const _orig = window.SwaggerUIBundle;
      window.SwaggerUIBundle = function(cfg) {
        const origOnComplete = cfg.onComplete;
        cfg.onComplete = function() {
          fetch('/auth/token')
            .then(r => r.json())
            .then(data => {
              if (data.token) {
                ui.preauthorizeApiKey('HTTPBearer', data.token);
                console.log('[authzen] Bearer token auto-applied from nginx OIDC session');
              }
            })
            .catch(e => console.warn('[authzen] Failed to fetch token:', e));
          if (origOnComplete) origOnComplete();
        };
        var ui = _orig(cfg);
        return ui;
      };
      Object.assign(window.SwaggerUIBundle, _orig);
    })();
    </script>
    """
    patched = html.body.decode().replace("</body>", auto_auth_script + "</body>")
    return HTMLResponse(content=patched, status_code=html.status_code)
