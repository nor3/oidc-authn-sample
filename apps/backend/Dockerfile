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

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
