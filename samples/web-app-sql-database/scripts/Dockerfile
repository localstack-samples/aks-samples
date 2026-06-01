# Stage 1 - Install build dependencies
FROM python:3.13-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV ACCEPT_EULA=Y

# Build tools + Microsoft ODBC Driver 18 (needed to compile pyodbc)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends msodbcsql18 unixodbc-dev \
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
ENV ACCEPT_EULA=Y

# Microsoft ODBC Driver 18 runtime libraries (loaded by pyodbc at runtime)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    unixodbc \
    && curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends msodbcsql18 \
    # Purge curl/gnupg WITHOUT --auto-remove: that flag prunes transitive deps apt
    # thinks are orphaned (libcurl4, libssl3, libkrb5-3, libgss3, …), which msodbcsql18
    # needs at runtime. The driver still loads but dlopen() fails, and unixODBC
    # reports the misleading "file not found" error.
    && apt-get purge -y curl gnupg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv

COPY app.py ./
COPY activities.py ./
COPY database.py ./
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
