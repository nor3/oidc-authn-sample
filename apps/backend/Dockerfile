FROM python:3.14.3-slim

WORKDIR /app

# 依存パッケージのインストール
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

# アプリケーションコードのコピー
COPY src/ ./src/

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 8000

# --proxy-headers: X-Forwarded-Proto を信頼し OpenAPI の servers URL を https:// で生成
# --forwarded-allow-ips=*: クラスタ内の ingress-nginx からのヘッダーを許可
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
