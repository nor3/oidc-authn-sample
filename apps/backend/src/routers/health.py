from fastapi import APIRouter

from ..config import settings

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    return {
        "status": "ok",
        "opa_middleware": settings.opa_middleware,
    }
