# KubeShip — shipping management API (FastAPI + Couchbase).
FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    "couchbase>=4.3,<5" \
    "fastapi>=0.115,<1" \
    "uvicorn[standard]>=0.32,<1" \
    "pydantic>=2.9,<3"

COPY src/ ./src/

ENV PORT=8080 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

EXPOSE 8080

USER 65532

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
