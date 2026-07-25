# Rituva API container — for Cloud Run (or any container host).
# Serves the FastAPI backend + the PWA at /app. Listens on $PORT (Cloud Run sets 8080).
#
# NOTE: rituva/ifct_local.py is gitignored AND .dockerignore'd, so the IFCT 2017 data
# is NOT baked into this image — the deployed product uses the base curated KB, which
# keeps it compliant with IFCT's terms until written permission is obtained.
FROM python:3.13-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8080

COPY requirements.txt .
# psycopg[binary] enables the Postgres backend (Cloud SQL); it is optional locally.
RUN pip install --no-cache-dir -r requirements.txt "psycopg[binary]>=3.1"

COPY rituva/ ./rituva/
COPY web/ ./web/

EXPOSE 8080
# exec form + shell so ${PORT} expands; single worker (Cloud Run scales by instances).
CMD ["sh", "-c", "uvicorn rituva.api:app --host 0.0.0.0 --port ${PORT}"]
