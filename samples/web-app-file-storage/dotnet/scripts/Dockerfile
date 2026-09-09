# Build stage: restore and publish the ASP.NET Core app with the .NET SDK image.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

WORKDIR /src

# Restore first so the package cache layer is reused when only sources change.
COPY VacationPlanner.csproj ./
RUN dotnet restore

COPY . ./
RUN dotnet publish -c Release -o /app/publish --no-restore

# Runtime stage: the ASP.NET Core runtime image only, no SDK.
FROM mcr.microsoft.com/dotnet/aspnet:10.0

# Port Kestrel listens on; kept as a build argument (and a runtime variable) as in the Python image.
ARG PORT=8080

# The app runs as a non-root user whose uid/gid are pinned to a known value: the app writes to an Azure file
# share, and the identity that must be able to write to it appears in the mount options of the SMB volume
# (uid=1000,gid=1000) and in the ownership of the NFS share. The runtime image ships a non-root `app` user
# (uid 1654) and, being Ubuntu-based, a default `ubuntu` account that already owns uid/gid 1000: the latter is
# dropped and `app` is re-numbered instead of adding a third account.
ARG APP_USER_UID=1000
ARG APP_USER_GID=1000

ENV PORT=${PORT}

WORKDIR /app
COPY --from=build /app/publish ./

RUN userdel --remove ubuntu \
    && groupmod --gid ${APP_USER_GID} app \
    && usermod --uid ${APP_USER_UID} --gid ${APP_USER_GID} app \
    && chown -R app:app /app /home/app
USER app
ENV HOME=/home/app

EXPOSE ${PORT}

ENTRYPOINT ["dotnet", "VacationPlanner.dll"]
