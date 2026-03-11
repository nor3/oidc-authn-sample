from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "AuthZEN Backend"
    debug: bool = False

    # OPA設定
    opa_url: str = "http://opa:8181"
    opa_middleware: bool = False
    opa_policy_path: str = "v1/data/authzen/api/allow"

    # CORS許可オリジン (カンマ区切り or リスト)
    cors_origins: list[str] = ["*"]

    model_config = {"env_prefix": ""}


settings = Settings()
