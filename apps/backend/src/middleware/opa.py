import httpx
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse


class OPAMiddleware(BaseHTTPMiddleware):
    """
    FastAPI ミドルウェアモードの PEP 実装。
    OPA_MIDDLEWARE=true の場合に有効になる。

    リクエスト毎に OPA REST API へ認可リクエストを送信し、
    allow=true の場合のみリクエストを通過させる。
    """

    def __init__(self, app, opa_url: str, policy_path: str):
        super().__init__(app)
        self.opa_url = opa_url
        self.policy_path = policy_path

    async def dispatch(self, request: Request, call_next):
        # ヘルスチェックはスキップ
        if request.url.path == "/health":
            return await call_next(request)

        auth_header = request.headers.get("authorization", "")
        token = auth_header.removeprefix("Bearer ").removeprefix("bearer ").strip()

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
