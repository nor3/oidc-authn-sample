from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "AuthZEN Backend"
    debug: bool = False

    # OPA設定
    opa_url: str = "http://opa:8181"
    opa_middleware: bool = False
    opa_policy_path: str = "v1/data/authzen/api/allow"

    model_config = {"env_prefix": ""}


settings = Settings()
