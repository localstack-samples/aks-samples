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

# Uid and gid of the user the app runs as. Unlike the other samples, these are pinned to a known
# value instead of being allocated by `adduser --system`: the app writes to an Azure file share, and
# the identity that must be able to write to it appears in the mount options of the SMB volume
# (uid=1000,gid=1000) and in the ownership of the NFS share. An unpredictable system uid would make
# the volume read-only for the app.
ARG APP_UID=1000
ARG APP_GID=1000

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/venv/bin:$PATH"
ENV PORT=${PORT}

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv

COPY app.py ./
COPY gunicorn.conf.py ./
COPY static ./static
COPY templates ./templates

RUN groupadd --gid ${APP_GID} app \
    && useradd --uid ${APP_UID} --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app \
    && chown -R app:app /app /home/app
USER app
ENV HOME=/home/app

EXPOSE ${PORT}

CMD ["sh", "-c", "exec gunicorn -c gunicorn.conf.py --bind 0.0.0.0:${PORT} --access-logfile - --error-logfile - app:app"]
