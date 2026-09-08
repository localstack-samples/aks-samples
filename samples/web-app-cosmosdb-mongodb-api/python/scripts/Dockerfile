# Stage 1 - Install build dependencies
FROM python:3.13-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Stage 2 - Runtime image
FROM python:3.13-slim

ARG PORT=8080

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/venv/bin:$PATH"
ENV PORT=${PORT}

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv

COPY app.py ./
COPY mongodb.py ./
COPY gunicorn.conf.py ./
COPY static ./static
COPY templates ./templates

RUN addgroup --system app \
    && adduser --system --ingroup app --home /home/app --shell /usr/sbin/nologin app \
    && chown -R app:app /app /home/app
USER app
ENV HOME=/home/app

EXPOSE ${PORT}

CMD ["sh", "-c", "exec gunicorn -c gunicorn.conf.py --bind 0.0.0.0:${PORT} --access-logfile - --error-logfile - app:app"]
