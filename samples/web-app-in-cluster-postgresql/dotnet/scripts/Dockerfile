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
ENV PORT=${PORT}

WORKDIR /app
COPY --from=build /app/publish ./

# Run as the runtime image's non-root `app` user, as the Python image runs as its own unprivileged `app` user.
USER app

EXPOSE ${PORT}

ENTRYPOINT ["dotnet", "VacationPlanner.dll"]
