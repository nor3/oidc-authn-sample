from fnmatch import fnmatch

import httpx
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

# デフォルトの OPA チェックスキップパターン（glob 形式）
DEFAULT_SKIP_PATTERNS: list[str] = [
    "/health",
    "/health/*",
    "/docs",
    "/docs/*",
    "/redoc",
    "/openapi.json",
    "/auth/token",
]


class OPAMiddleware(BaseHTTPMiddleware):
    """
    FastAPI ミドルウェアモードの PEP 実装。
    OPA_MIDDLEWARE=true の場合に有効になる。

    リクエスト毎に OPA REST API へ認可リクエストを送信し、
    allow=true の場合のみリクエストを通過させる。

    skip_patterns: OPA チェックをスキップするパスの glob パターンリスト。
                   省略時は DEFAULT_SKIP_PATTERNS を使用。
    """

    def __init__(
        self,
        app,
        opa_url: str,
        policy_path: str,
        skip_patterns: list[str] | None = None,
    ):
        super().__init__(app)
        self.opa_url = opa_url
        self.policy_path = policy_path
        self.skip_patterns = skip_patterns if skip_patterns is not None else DEFAULT_SKIP_PATTERNS

    def _should_skip(self, path: str) -> bool:
        return any(fnmatch(path, pattern) for pattern in self.skip_patterns)

    async def dispatch(self, request: Request, call_next):
        if self._should_skip(request.url.path):
            return await call_next(request)

        auth_header = request.headers.get("authorization", "")
        token = auth_header.removeprefix("Bearer ").removeprefix("bearer ").strip()

        # oauth2-proxy proxy モードでは access token が X-Forwarded-Access-Token で届く
        if not token:
            token = request.headers.get("x-forwarded-access-token", "").strip()

        if not token:
            return JSONResponse(
                status_code=401,
                content={"detail": "Authorization header missing"},
            )

        opa_input = {
            "input": {
                "token": token,
                "method": request.method,
                "path": request.url.path,
                "query": dict(request.query_params),
            }
        }

        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post(
                    f"{self.opa_url}/{self.policy_path}",
                    json=opa_input,
                    timeout=5.0,
                )
                resp.raise_for_status()
                result = resp.json()
        except httpx.HTTPError as e:
            return JSONResponse(
                status_code=503,
                content={"detail": f"OPA request failed: {e}"},
            )

        if not result.get("result", False):
            return JSONResponse(status_code=403, content={"detail": "Forbidden"})

        return await call_next(request)
