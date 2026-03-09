from fastapi import FastAPI

from .config import settings
from .middleware.opa import OPAMiddleware
from .routers import documents, health

app = FastAPI(
    title=settings.app_name,
    description="OPA認可デモ用サンプルREST API",
    version="1.0.0",
)

if settings.opa_middleware:
    app.add_middleware(
        OPAMiddleware,
        opa_url=settings.opa_url,
        policy_path=settings.opa_policy_path,
    )

app.include_router(health.router)
app.include_router(documents.router, prefix="/api/v1")
